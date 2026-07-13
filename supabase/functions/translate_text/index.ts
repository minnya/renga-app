// design/system.md 6.5節「テキスト翻訳」に対応するEdge Function。投稿本文/DMメッセージ本文を
// Google Cloud Translation API (v2, Basic) でtarget_localeへ翻訳する。Geminiより安価かつ
// 翻訳専用サービスのため、翻訳という用途にはこちらを使う。label_post_domainと同じ認証パターン
// （Authorizationヘッダーのユーザーjwt検証のみ）に倣うが、DB更新は行わずtarget_localeへの
// 翻訳結果のみを返す（design/product.md 3.12.1節: 翻訳結果はDBに保存しない）。

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

const TRANSLATE_ENDPOINT = 'https://translation.googleapis.com/language/translate/v2';

const SUPPORTED_LOCALES = ['en', 'ja'];

type TranslatePayload = { text: string; target_locale: string };

const TRANSLATE_MAX_ATTEMPTS = 3;
const TRANSLATE_RETRY_BASE_DELAY_MS = 2000;

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Google Cloud Translation API (v2) はAPIキーのみでの呼び出しに対応しており、
// label_post_domain（Gemini）のようなサービスアカウント/OAuth2は不要。
async function runGoogleTranslation(text: string, targetLocale: string): Promise<string | null> {
  const apiKey = Deno.env.get('GOOGLE_TRANSLATE_API_KEY');
  if (!apiKey) {
    console.error('translate_text: GOOGLE_TRANSLATE_API_KEY is not configured');
    return null;
  }

  for (let attempt = 1; attempt <= TRANSLATE_MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(`${TRANSLATE_ENDPOINT}?key=${apiKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          q: text,
          target: targetLocale,
          format: 'text',
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        const retryable = response.status === 429 || response.status === 503;
        console.error(
          'translate_text: Google Translate API call failed',
          response.status,
          errorBody,
          retryable ? `(attempt ${attempt}/${TRANSLATE_MAX_ATTEMPTS}, will retry)` : '(not retryable)',
        );
        if (retryable && attempt < TRANSLATE_MAX_ATTEMPTS) {
          await sleepMs(TRANSLATE_RETRY_BASE_DELAY_MS * attempt);
          continue;
        }
        return null;
      }

      const json = await response.json();
      const translatedText = json?.data?.translations?.[0]?.translatedText;
      if (typeof translatedText !== 'string') {
        console.error('translate_text: unexpected Google Translate response shape', json);
        return null;
      }

      return translatedText;
    } catch (error) {
      console.error(
        'translate_text: Google Translate API call threw an error',
        error,
        `(attempt ${attempt}/${TRANSLATE_MAX_ATTEMPTS})`,
      );
      if (attempt < TRANSLATE_MAX_ATTEMPTS) {
        await sleepMs(TRANSLATE_RETRY_BASE_DELAY_MS * attempt);
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

  const translated = await runGoogleTranslation(payload.text, payload.target_locale);
  if (translated === null) {
    return jsonResponse({ error: 'translation failed' }, 502);
  }

  return jsonResponse({ translated_text: translated }, 200);
});
