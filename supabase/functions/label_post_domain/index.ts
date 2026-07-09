// design/system.md 6.1節「ドメインラベリング（サイレント・ドメイン・マッピング）」に対応する
// Edge Function。投稿テキストをGeminiに送信し、日本標準産業分類の大分類20区分の固定タクソノミー
// から該当するドメインラベル（複数可・最大3つ）＋信頼度を推定させ、`posts.domain_labels` に反映する。
//
// - Gemini APIキーはFunction Secrets（`GEMINI_API_KEY`）としてのみ保持する（moderate_contentと同様）。
// - ドメインラベル付与はベストエフォートの補助機能であり、投稿自体の処理を止めてはならないため、
//   Gemini呼び出し失敗・JSONパース失敗時は何もせず200を返す
//   （design/system.md 6.1節「パース失敗時はラベル付与をスキップして処理を継続する」）。
// - 呼び出し元はFlutterアプリの認証済みユーザーアクションとして非同期に叩く想定。
//   cron secretではなく、AuthorizationヘッダーのユーザーJWTが有効であることのみ確認する
//   （createClientにAuthorizationヘッダーを渡してsupabase.auth.getUser()で検証）。
//   DB更新自体はRLSの影響を受けないよう別途service roleクライアントで行う。

import { createClient } from 'jsr:@supabase/supabase-js@2';

// Flutter Web（ブラウザ）の投稿フローから直接呼び出されるため、CORSプリフライト（OPTIONS）と
// すべてのレスポンスへのAccess-Control-Allow-Originヘッダーが必須（create_mux_uploadと同様）。
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const GEMINI_MODEL = 'gemini-3-flash-preview';
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

// 日本標準産業分類の大分類20区分。他ファイルとは共有しない定数（フロントエンド側は別途同じリストを持つ想定）。
const DOMAIN_TAXONOMY = [
  '農業_林業',
  '漁業',
  '鉱業_採石業_砂利採取業',
  '建設業',
  '製造業',
  '電気_ガス_熱供給_水道業',
  '情報通信業',
  '運輸業_郵便業',
  '卸売業_小売業',
  '金融業_保険業',
  '不動産業_物品賃貸業',
  '学術研究_専門技術サービス業',
  '宿泊業_飲食サービス業',
  '生活関連サービス業_娯楽業',
  '教育_学習支援業',
  '医療_福祉',
  '複合サービス事業',
  'サービス業_他に分類されないもの',
  '公務',
  '分類不能の産業',
];

const MIN_TEXT_LENGTH = 20;
const MIN_CONFIDENCE = 0.5;
const MAX_LABELS = 3;

type LabelPayload = { post_id: string; text: string };
type GeminiLabel = { label: string; confidence: number };

function buildPrompt(text: string): string {
  return `あなたは投稿テキストを産業分類にラベリングするアシスタントです。
以下のテキストが、次の固定タクソノミー（日本標準産業分類の大分類）のうちどれに関連するかを判定してください。
関連する可能性のあるラベルを最大3つまで、それぞれの信頼度スコア(0〜1)とともに挙げてください。
明確に関連しないラベルは含めないでください。

タクソノミー:
${DOMAIN_TAXONOMY.join(', ')}

判定結果は必ず以下の厳密なJSON形式のみで返してください。説明文やMarkdownのコードフェンスは一切含めないでください:
{"labels": [{"label": string, "confidence": number}]}

- labelには上記タクソノミーの文字列をそのまま使用してください（タクソノミーにない文字列は返さないでください）。
- 該当するラベルがなければ空配列を返してください。
- 最大3件までとしてください。

--- 対象テキスト ---
${text}
`;
}

function parseGeminiLabels(rawText: string): GeminiLabel[] | null {
  try {
    const cleaned = rawText
      .trim()
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/```\s*$/i, '')
      .trim();
    const parsed = JSON.parse(cleaned);

    if (!Array.isArray(parsed?.labels)) return null;

    const labels: GeminiLabel[] = parsed.labels
      // deno-lint-ignore no-explicit-any
      .filter((entry: any) =>
        entry &&
        typeof entry.label === 'string' &&
        DOMAIN_TAXONOMY.includes(entry.label) &&
        typeof entry.confidence === 'number' &&
        !Number.isNaN(entry.confidence)
      )
      // deno-lint-ignore no-explicit-any
      .map((entry: any) => ({ label: entry.label, confidence: entry.confidence }));

    return labels;
  } catch (error) {
    console.error('label_post_domain: failed to parse Gemini response JSON', error, rawText);
    return null;
  }
}

const GEMINI_MAX_ATTEMPTS = 3;
const GEMINI_RETRY_BASE_DELAY_MS = 3000;

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// `gemini-3-flash-preview`はプレビューモデルのため「高負荷につき503」を一時的に
// 返すことがある。429/503は指数バックオフでリトライする。
async function runGeminiLabeling(text: string): Promise<GeminiLabel[] | null> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    console.error('label_post_domain: GEMINI_API_KEY is not configured; skipping labeling');
    return null;
  }

  for (let attempt = 1; attempt <= GEMINI_MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(`${GEMINI_ENDPOINT}?key=${apiKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: buildPrompt(text) }] }],
          generationConfig: {
            temperature: 0,
            responseMimeType: 'application/json',
          },
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        const retryable = response.status === 429 || response.status === 503;
        console.error(
          'label_post_domain: Gemini API call failed',
          response.status,
          errorBody,
          retryable ? `(attempt ${attempt}/${GEMINI_MAX_ATTEMPTS}, will retry)` : '(not retryable)',
        );
        if (retryable && attempt < GEMINI_MAX_ATTEMPTS) {
          await sleepMs(GEMINI_RETRY_BASE_DELAY_MS * attempt);
          continue;
        }
        return null;
      }

      const json = await response.json();
      const rawText = json?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof rawText !== 'string') {
        console.error('label_post_domain: unexpected Gemini response shape', json);
        return null;
      }

      return parseGeminiLabels(rawText);
    } catch (error) {
      console.error('label_post_domain: Gemini API call threw an error', error, `(attempt ${attempt}/${GEMINI_MAX_ATTEMPTS})`);
      if (attempt < GEMINI_MAX_ATTEMPTS) {
        await sleepMs(GEMINI_RETRY_BASE_DELAY_MS * attempt);
        continue;
      }
      return null;
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'method not allowed' }, 405);
  }

  let payload: LabelPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'invalid JSON body' }, 400);
  }

  if (!payload.post_id || typeof payload.text !== 'string') {
    return jsonResponse({ error: 'post_id and text are required' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'server misconfigured' }, 500);
  }

  // Authorizationヘッダーのユーザーjwtが有効かどうかのみ確認する（誰でも叩ける状態を避けるため）。
  // service roleキーが渡された場合はバックフィル用の管理スクリプトからの呼び出しとして許可する
  // （既存投稿への遡及ラベル付け用。通常のクライアントからのフローではservice roleキーは使わない）。
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }
  const isServiceRoleCaller = authHeader === `Bearer ${serviceRoleKey}`;
  if (!isServiceRoleCaller) {
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? serviceRoleKey;
    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await authClient.auth.getUser();
    if (userError || !userData?.user) {
      return jsonResponse({ error: 'unauthorized' }, 401);
    }
  }

  // 短すぎる投稿はGemini呼び出し自体を行わずコストを節約する。
  if (payload.text.trim().length < MIN_TEXT_LENGTH) {
    return jsonResponse({ labeled: false }, 200);
  }

  const labels = await runGeminiLabeling(payload.text);
  if (labels === null) {
    // Gemini呼び出し失敗・パース失敗時はベストエフォートなので何もせず200を返す。
    return jsonResponse({ labeled: false }, 200);
  }

  const adopted = labels
    .filter((l) => l.confidence >= MIN_CONFIDENCE)
    .slice(0, MAX_LABELS)
    .map((l) => l.label);

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { error: updateError } = await supabase
    .from('posts')
    .update({ domain_labels: adopted })
    .eq('id', payload.post_id);

  if (updateError) {
    console.error('label_post_domain: failed to update posts.domain_labels', updateError);
    // ベストエフォートのため失敗しても200で返す。
    return jsonResponse({ labeled: false }, 200);
  }

  return jsonResponse({ labeled: true, labels: adopted }, 200);
});
