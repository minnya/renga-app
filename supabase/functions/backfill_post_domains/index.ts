// design/system.md 6.1節「ドメインラベリング」。`label_post_domain` は投稿作成時にのみ
// 呼ばれるため、それ以前に作成された投稿や、何らかの理由でラベル付けに失敗した投稿は
// `domain_labels` が空のまま残ることがある。本Functionはその遡及バックフィル用。
//
// - `posts` から `domain_labels` が空かつ本文20文字以上の投稿を古い順に一定件数（デフォルト20件）
//   取得し、`label_post_domain` と同じロジックでGeminiにラベリングさせて `domain_labels` を更新する。
// - 冪等（既にラベル付け済みの投稿は対象外）なので、残件がなくなるまで何度呼び出しても安全。
// - `recalculate_scores` / `generate_quiz_batch` と同じ `X-Cron-Secret` パターンで保護する
//   （環境変数名: `BACKFILL_CRON_SECRET`）。運用者が手動で叩く想定。
// - Gemini無料枠のレート制限を考慮し、1件ごとに約3秒のディレイを挟む。

import { createClient } from 'jsr:@supabase/supabase-js@2';

const GEMINI_MODEL = 'gemini-3-flash-preview';
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

// label_post_domainと同じタクソノミー（posts.domain_labels / domain_scores.domainと一致させる）。
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
const DEFAULT_BATCH_SIZE = 20;
const GEMINI_MAX_ATTEMPTS = 3;
const GEMINI_RETRY_BASE_DELAY_MS = 3000;
const INTER_POST_DELAY_MS = 3000;

type GeminiLabel = { label: string; confidence: number };

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

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

// Geminiは`responseMimeType: 'application/json'`指定時でも、まれに有効なJSONオブジェクトの後に
// 余分なテキストを付け足すことがあるため、波括弧の深さを数えて最初の完全なJSONオブジェクトのみを抽出する。
function extractJsonObject(rawText: string): string {
  const stripped = rawText
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim();

  const start = stripped.indexOf('{');
  if (start === -1) return stripped;

  let depth = 0;
  let inString = false;
  let escapeNext = false;
  for (let i = start; i < stripped.length; i++) {
    const ch = stripped[i];
    if (escapeNext) {
      escapeNext = false;
      continue;
    }
    if (ch === '\\') {
      escapeNext = true;
      continue;
    }
    if (ch === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (ch === '{') depth++;
    if (ch === '}') {
      depth--;
      if (depth === 0) return stripped.slice(start, i + 1);
    }
  }
  return stripped;
}

function parseGeminiLabels(rawText: string): GeminiLabel[] | null {
  try {
    const cleaned = extractJsonObject(rawText);
    const parsed = JSON.parse(cleaned);
    if (!Array.isArray(parsed?.labels)) return null;

    return parsed.labels
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
  } catch (error) {
    console.error('backfill_post_domains: failed to parse Gemini response JSON', error, rawText);
    return null;
  }
}

async function runGeminiLabeling(apiKey: string, text: string): Promise<GeminiLabel[] | null> {
  for (let attempt = 1; attempt <= GEMINI_MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(`${GEMINI_ENDPOINT}?key=${apiKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: buildPrompt(text) }] }],
          generationConfig: { temperature: 0, responseMimeType: 'application/json' },
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        const retryable = response.status === 429 || response.status === 503;
        console.error('backfill_post_domains: Gemini API call failed', response.status, errorBody);
        if (retryable && attempt < GEMINI_MAX_ATTEMPTS) {
          await sleepMs(GEMINI_RETRY_BASE_DELAY_MS * attempt);
          continue;
        }
        return null;
      }

      const json = await response.json();
      const rawText = json?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof rawText !== 'string') {
        console.error('backfill_post_domains: unexpected Gemini response shape', json);
        return null;
      }
      return parseGeminiLabels(rawText);
    } catch (error) {
      console.error('backfill_post_domains: Gemini API call threw an error', error);
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
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405 });
  }

  const cronSecret = Deno.env.get('BACKFILL_CRON_SECRET');
  if (!cronSecret) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }
  if (req.headers.get('X-Cron-Secret') !== cronSecret) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }

  const apiKey = Deno.env.get('GEMINI_API_KEY');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!apiKey || !supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  let batchSize = DEFAULT_BATCH_SIZE;
  try {
    const body = await req.json();
    if (typeof body?.batch_size === 'number' && body.batch_size > 0) {
      batchSize = Math.min(body.batch_size, 50);
    }
  } catch {
    // ボディなし・不正JSONはデフォルトのbatchSizeで続行する。
  }

  // domain_labels が空（未ラベル付け）かつ本文が一定文字数以上の投稿を古い順に取得する。
  const { data: candidates, error: selectError } = await supabase
    .from('posts')
    .select('id, body')
    .eq('domain_labels', '{}')
    .order('created_at', { ascending: true })
    .limit(batchSize * 3); // 文字数フィルタはクライアント側で行うため多めに取得する

  if (selectError) {
    console.error('backfill_post_domains: failed to select candidate posts', selectError);
    return new Response(JSON.stringify({ error: selectError.message }), { status: 500 });
  }

  const eligible = (candidates ?? [])
    .filter((p) => typeof p.body === 'string' && p.body.trim().length >= MIN_TEXT_LENGTH)
    .slice(0, batchSize);

  let labeledCount = 0;
  let failedCount = 0;

  for (let i = 0; i < eligible.length; i++) {
    const post = eligible[i];
    const labels = await runGeminiLabeling(apiKey, post.body as string);
    if (labels === null) {
      failedCount++;
    } else {
      const adopted = labels
        .filter((l) => l.confidence >= MIN_CONFIDENCE)
        .slice(0, MAX_LABELS)
        .map((l) => l.label);

      const { error: updateError } = await supabase
        .from('posts')
        .update({ domain_labels: adopted })
        .eq('id', post.id);

      if (updateError) {
        console.error('backfill_post_domains: failed to update post', post.id, updateError);
        failedCount++;
      } else {
        labeledCount++;
      }
    }

    if (i < eligible.length - 1) {
      await sleepMs(INTER_POST_DELAY_MS);
    }
  }

  return new Response(
    JSON.stringify({
      candidates_found: eligible.length,
      labeled: labeledCount,
      failed: failedCount,
      // batchSize件ちょうど処理できた場合、まだ残っている可能性があるため再実行を促す。
      may_have_more: eligible.length === batchSize,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
