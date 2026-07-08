// design/product.md 3.9節「通報・コンテンツモデレーション」・design/system.md 13章
// 「コンテンツモデレーション・Trust & Safety」の一次自動チェックを行うEdge Function。
//
// 投稿（テキスト・画像・動画サムネイル）をGemini (multimodal) に送信し、暴力・性的コンテンツ・
// ヘイトスピーチ・自傷/自殺関連・CSAM等のカテゴリ抵触有無を判定させ、`moderation_checks` に
// 記録したうえで `flagged` 判定の場合は該当投稿の `reach_score` を 0 にして公開停止する。
//
// - Gemini APIキーはFunction Secrets（`GEMINI_API_KEY`）としてのみ保持し、クライアントには渡さない
//   （system.md 11.4節 / 12章）。
// - service role キーでDBを更新するため、RLSをバイパスして直接書き込む（mux_webhookと同様のパターン）。
// - CSAM（児童性的搾取コンテンツ）相当のカテゴリが少しでも検出された場合は、信頼度の高低に関わらず
//   無条件で `flagged` として扱う。「疑わしきは非表示を優先する」という13.1節の方針に基づき、
//   false negative（見逃し）のコストが著しく大きい領域のため確認バイアスをそちら側に寄せる。
// - Gemini APIキー未設定・呼び出し失敗・レスポンスのJSONパース失敗時は、例外を投げて処理全体を
//   止めるのではなく安全側（`human_review`）に倒してログを残し、可用性を優先して処理を継続する。

import { createClient } from 'jsr:@supabase/supabase-js@2';

const GEMINI_MODEL = 'gemini-1.5-flash';
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

// Geminiに判定させるカテゴリの語彙。CSAMは特別扱いするため文字列で明示的に判定する。
const CSAM_CATEGORY = 'csam';
const KNOWN_CATEGORIES = ['violence', 'sexual_content', 'hate_speech', 'self_harm', CSAM_CATEGORY];

type Verdict = 'approved' | 'flagged' | 'human_review';

type ModerationPayload = {
  target_type: 'post' | 'video';
  target_id: string;
  text?: string;
  image_url?: string;
  video_thumbnail_url?: string;
};

type ModerationResult = {
  verdict: Verdict;
  categories: string[];
  confidence: number | null;
};

// 安全側（human_review）のデフォルト結果。Gemini呼び出し不可・パース失敗時に使う。
function fallbackResult(): ModerationResult {
  return { verdict: 'human_review', categories: [], confidence: null };
}

function buildPrompt(text?: string): string {
  return `あなたはUGC（ユーザー生成コンテンツ）のコンテンツモデレーターです。
以下のテキストおよび（添付されている場合は）画像を確認し、次のカテゴリへの抵触有無を判定してください:
- violence（暴力的表現）
- sexual_content（性的コンテンツ）
- hate_speech（ヘイトスピーチ・誹謗中傷）
- self_harm（自傷・自殺関連）
- csam（児童の性的搾取に関連する疑いのあるコンテンツ）

判定結果は必ず以下の厳密なJSON形式のみで返してください。説明文やMarkdownのコードフェンスは一切含めないでください:
{"verdict": "approved" | "flagged" | "human_review", "categories": string[], "confidence": number}

- verdictは、明確に問題がなければ"approved"、明確に問題があれば"flagged"、
  判断に迷うグレーゾーンであれば"human_review"としてください。
- categoriesには該当した（または疑いのある）カテゴリのキーのみを含めてください（該当なしなら空配列）。
- confidenceは0から1の判定確信度です。
- 少しでもcsamに該当する疑いがある場合は、confidenceの値に関わらずcategoriesに"csam"を含め、
  verdictは"flagged"としてください（疑わしきは非表示を優先するため）。

--- 対象テキスト ---
${text?.trim() ? text : '(テキストなし)'}
`;
}

// 画像URLを取得してGeminiのinlineData（base64）用に変換する。
// 取得できない場合はnullを返し、テキストのみで判定を続行する。
async function fetchImageAsInlineData(
  imageUrl: string,
): Promise<{ mimeType: string; data: string } | null> {
  try {
    const response = await fetch(imageUrl);
    if (!response.ok) return null;
    const contentType = response.headers.get('Content-Type') ?? 'image/jpeg';
    const buffer = await response.arrayBuffer();
    const base64 = btoa(
      Array.from(new Uint8Array(buffer))
        .map((byte) => String.fromCharCode(byte))
        .join(''),
    );
    return { mimeType: contentType.split(';')[0].trim(), data: base64 };
  } catch (error) {
    console.error('moderate_content: failed to fetch image for inline data', error);
    return null;
  }
}

function parseGeminiJson(rawText: string): ModerationResult | null {
  try {
    // Geminiがコードフェンス（```json ... ```）で包んで返す場合があるため除去する。
    const cleaned = rawText
      .trim()
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/```\s*$/i, '')
      .trim();
    const parsed = JSON.parse(cleaned);

    const verdictRaw = parsed?.verdict;
    const verdict: Verdict =
      verdictRaw === 'approved' || verdictRaw === 'flagged' || verdictRaw === 'human_review'
        ? verdictRaw
        : 'human_review';

    const categories: string[] = Array.isArray(parsed?.categories)
      ? parsed.categories.filter((c: unknown) => typeof c === 'string')
      : [];

    const confidenceRaw = parsed?.confidence;
    const confidence = typeof confidenceRaw === 'number' && !Number.isNaN(confidenceRaw)
      ? confidenceRaw
      : null;

    return { verdict, categories, confidence };
  } catch (error) {
    console.error('moderate_content: failed to parse Gemini response JSON', error, rawText);
    return null;
  }
}

async function runGeminiModeration(payload: ModerationPayload): Promise<ModerationResult> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    console.error('moderate_content: GEMINI_API_KEY is not configured; falling back to human_review');
    return fallbackResult();
  }

  const imageUrl = payload.image_url ?? payload.video_thumbnail_url;
  // deno-lint-ignore no-explicit-any
  const parts: any[] = [{ text: buildPrompt(payload.text) }];

  if (imageUrl) {
    const inlineImage = await fetchImageAsInlineData(imageUrl);
    if (inlineImage) {
      parts.push({ inlineData: { mimeType: inlineImage.mimeType, data: inlineImage.data } });
    }
  }

  try {
    const response = await fetch(`${GEMINI_ENDPOINT}?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts }],
        generationConfig: {
          temperature: 0,
          responseMimeType: 'application/json',
        },
      }),
    });

    if (!response.ok) {
      const errorBody = await response.text();
      console.error('moderate_content: Gemini API call failed', response.status, errorBody);
      return fallbackResult();
    }

    const json = await response.json();
    const rawText = json?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof rawText !== 'string') {
      console.error('moderate_content: unexpected Gemini response shape', json);
      return fallbackResult();
    }

    const parsed = parseGeminiJson(rawText);
    if (!parsed) {
      return fallbackResult();
    }

    // CSAM相当のカテゴリが検出された場合は、信頼度・元のverdictに関わらず無条件でflaggedにする。
    // 「疑わしきは非表示を優先する」（system.md 13.1節）という方針をここで強制する。
    if (parsed.categories.includes(CSAM_CATEGORY)) {
      return { ...parsed, verdict: 'flagged' };
    }

    return parsed;
  } catch (error) {
    console.error('moderate_content: Gemini API call threw an error', error);
    return fallbackResult();
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405 });
  }

  let payload: ModerationPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid JSON body' }), { status: 400 });
  }

  if (
    (payload.target_type !== 'post' && payload.target_type !== 'video') ||
    !payload.target_id
  ) {
    return new Response(
      JSON.stringify({ error: 'target_type ("post" | "video") and target_id are required' }),
      { status: 400 },
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const result = await runGeminiModeration(payload);

  // checked_content: 監査ログとして何を判定対象にしたかを記録しておく（画像/動画URLも含める）。
  const checkedContentParts = [
    payload.text ? `text: ${payload.text}` : null,
    payload.image_url ? `image_url: ${payload.image_url}` : null,
    payload.video_thumbnail_url ? `video_thumbnail_url: ${payload.video_thumbnail_url}` : null,
  ].filter(Boolean);
  const checkedContent = checkedContentParts.length > 0
    ? checkedContentParts.join('\n')
    : '(no content)';

  const { error: insertError } = await supabase.from('moderation_checks').insert({
    target_type: payload.target_type,
    target_id: payload.target_id,
    checked_content: checkedContent,
    model: GEMINI_MODEL,
    verdict: result.verdict,
    categories: result.categories,
    confidence: result.confidence,
  });

  if (insertError) {
    console.error('moderate_content: failed to insert moderation_checks row', insertError);
    return new Response(JSON.stringify({ error: insertError.message }), { status: 500 });
  }

  if (result.verdict === 'flagged') {
    if (payload.target_type === 'post') {
      const { error: updateError } = await supabase
        .from('posts')
        .update({ reach_score: 0 })
        .eq('id', payload.target_id);

      if (updateError) {
        console.error('moderate_content: failed to shadow-hide post', updateError);
        return new Response(JSON.stringify({ error: updateError.message }), { status: 500 });
      }
    } else {
      // videoの場合はvideos.post_idを辿って対象投稿のreach_scoreを0にする。
      const { data: video, error: videoLookupError } = await supabase
        .from('videos')
        .select('post_id')
        .eq('id', payload.target_id)
        .maybeSingle();

      if (videoLookupError) {
        console.error('moderate_content: failed to look up video for shadow-hide', videoLookupError);
        return new Response(JSON.stringify({ error: videoLookupError.message }), { status: 500 });
      }

      if (video?.post_id) {
        const { error: updateError } = await supabase
          .from('posts')
          .update({ reach_score: 0 })
          .eq('id', video.post_id);

        if (updateError) {
          console.error('moderate_content: failed to shadow-hide post for video', updateError);
          return new Response(JSON.stringify({ error: updateError.message }), { status: 500 });
        }
      }
    }
  }

  return new Response(
    JSON.stringify({
      verdict: result.verdict,
      categories: result.categories,
      confidence: result.confidence,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
