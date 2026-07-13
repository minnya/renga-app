// design/system.md 6.5節「テキスト翻訳」に対応するEdge Function。投稿本文/DMメッセージ本文を
// Geminiでtarget_localeへ翻訳する。label_post_domainと同じ認証パターン（Authorizationヘッダーの
// ユーザーJWT検証のみ）に倣うが、DB更新は行わずtarget_localeへの翻訳結果のみを返す
// （design/product.md 3.12.1節: 翻訳結果はDBに保存しない）。

import { createClient } from 'jsr:@supabase/supabase-js@2';

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

const GEMINI_MODEL = 'gemini-3.1-flash-lite';
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const SUPPORTED_LOCALES = ['en', 'ja'];

type TranslatePayload = { text: string; target_locale: string };

function buildPrompt(text: string, targetLocale: string): string {
  const targetLanguageName = targetLocale === 'ja' ? '日本語' : '英語';
  return `以下のテキストを${targetLanguageName}に翻訳してください。翻訳結果のみを返し、
説明・前置き・Markdownのコードフェンスは一切含めないでください。
既に${targetLanguageName}で書かれている場合は、そのままの文章を返してください。

判定結果は必ず以下の厳密なJSON形式のみで返してください:
{"translated_text": string}

--- 対象テキスト ---
${text}
`;
}

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

function parseTranslatedText(rawText: string): string | null {
  try {
    const cleaned = extractJsonObject(rawText);
    const parsed = JSON.parse(cleaned);
    if (typeof parsed?.translated_text !== 'string') return null;
    return parsed.translated_text;
  } catch (error) {
    console.error('translate_text: failed to parse Gemini response JSON', error, rawText);
    return null;
  }
}

const GEMINI_MAX_ATTEMPTS = 3;
const GEMINI_RETRY_BASE_DELAY_MS = 3000;

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runGeminiTranslation(text: string, targetLocale: string): Promise<string | null> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    console.error('translate_text: GEMINI_API_KEY is not configured');
    return null;
  }

  for (let attempt = 1; attempt <= GEMINI_MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(`${GEMINI_ENDPOINT}?key=${apiKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: buildPrompt(text, targetLocale) }] }],
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
          'translate_text: Gemini API call failed',
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
        console.error('translate_text: unexpected Gemini response shape', json);
        return null;
      }

      return parseTranslatedText(rawText);
    } catch (error) {
      console.error('translate_text: Gemini API call threw an error', error, `(attempt ${attempt}/${GEMINI_MAX_ATTEMPTS})`);
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

  let payload: TranslatePayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'invalid JSON body' }, 400);
  }

  if (typeof payload.text !== 'string' || payload.text.trim().length === 0) {
    return jsonResponse({ error: 'text is required' }, 400);
  }
  if (!SUPPORTED_LOCALES.includes(payload.target_locale)) {
    return jsonResponse({ error: 'target_locale must be one of en, ja' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'server misconfigured' }, 500);
  }

  // Authorizationヘッダーのユーザーjwtが有効かどうかのみ確認する（label_post_domainと同様）。
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? serviceRoleKey;
  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  const translated = await runGeminiTranslation(payload.text, payload.target_locale);
  if (translated === null) {
    return jsonResponse({ error: 'translation failed' }, 502);
  }

  return jsonResponse({ translated_text: translated }, 200);
});
