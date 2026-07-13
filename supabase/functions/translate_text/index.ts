// design/system.md 6.5節「テキスト翻訳」に対応するEdge Function。投稿本文/DMメッセージ本文を
// Google Cloud Translation API v3 (Advanced) でtarget_localeへ翻訳する。Geminiより安価かつ
// 翻訳専用サービスのため、翻訳という用途にはこちらを使う。認証は`send_push_notification`と同じ
// Firebase Admin SDKサービスアカウントJSON（Supabase Function Secrets
// `FIREBASE_SERVICE_ACCOUNT_JSON`）を使ったOAuth2（自己署名JWT→アクセストークン交換）を再利用する
// （同じGCPプロジェクトのサービスアカウントに`Cloud Translation API User`ロールを追加付与済み）。
// ユーザー認証はlabel_post_domainと同じパターン（Authorizationヘッダーのユーザーjwt検証のみ）に倣うが、
// DB更新は行わずtarget_localeへの翻訳結果のみを返す（design/product.md 3.12.1節: DBに保存しない）。

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

const SUPPORTED_LOCALES = ['en', 'ja'];
const CLOUD_PLATFORM_SCOPE = 'https://www.googleapis.com/auth/cloud-platform';
const GOOGLE_TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';

type TranslatePayload = { text: string; target_locale: string };

interface FirebaseServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

// PEM形式の秘密鍵をWeb Crypto APIで読み込めるバイナリ(ArrayBuffer)に変換する
// （send_push_notificationと同じ実装）。
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function base64UrlEncode(input: ArrayBuffer | string): string {
  let bytes: Uint8Array;
  if (typeof input === 'string') {
    bytes = new TextEncoder().encode(input);
  } else {
    bytes = new Uint8Array(input);
  }
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// サービスアカウントJSON（RS256秘密鍵）でJWTを自己署名し、Google OAuth2トークンエンドポイントで
// Cloud Translation API呼び出し用のアクセストークンに交換する（send_push_notificationと同じ実装）。
async function getCloudPlatformAccessToken(serviceAccount: FirebaseServiceAccount): Promise<string> {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claimSet = {
    iss: serviceAccount.client_email,
    scope: CLOUD_PLATFORM_SCOPE,
    aud: GOOGLE_TOKEN_ENDPOINT,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };

  const unsignedJwt = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claimSet))}`;

  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedJwt),
  );
  const signedJwt = `${unsignedJwt}.${base64UrlEncode(signatureBuffer)}`;

  const tokenResponse = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: signedJwt,
    }),
  });

  if (!tokenResponse.ok) {
    const errorBody = await tokenResponse.text();
    throw new Error(`failed to obtain Cloud Translation access token: ${errorBody}`);
  }

  const tokenJson = await tokenResponse.json();
  return tokenJson.access_token as string;
}

async function runGoogleTranslation(
  serviceAccount: FirebaseServiceAccount,
  text: string,
  targetLocale: string,
): Promise<string | null> {
  try {
    const accessToken = await getCloudPlatformAccessToken(serviceAccount);
    const response = await fetch(
      `https://translation.googleapis.com/v3/projects/${serviceAccount.project_id}/locations/global:translateText`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: [text],
          targetLanguageCode: targetLocale,
          mimeType: 'text/plain',
        }),
      },
    );

    if (!response.ok) {
      const errorBody = await response.text();
      console.error('translate_text: Cloud Translation API call failed', response.status, errorBody);
      return null;
    }

    const json = await response.json();
    const translatedText = json?.translations?.[0]?.translatedText;
    if (typeof translatedText !== 'string') {
      console.error('translate_text: unexpected Cloud Translation API response shape', json);
      return null;
    }
    return translatedText;
  } catch (error) {
    console.error('translate_text: Cloud Translation API call threw an error', error);
    return null;
  }
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
  // Function Secretsへ生JSONをそのまま設定すると、CLI/シェル経由の設定時に埋め込みの
  // 改行・引用符がプラットフォーム（特にWindows）依存のクォーティング処理で壊れることがあるため、
  // base64エンコードした文字列（`FIREBASE_SERVICE_ACCOUNT_JSON_B64`）として保持しデコードする。
  const serviceAccountJsonB64 = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON_B64');
  if (!supabaseUrl || !serviceRoleKey || !serviceAccountJsonB64) {
    return jsonResponse({ error: 'server misconfigured' }, 500);
  }

  let serviceAccount: FirebaseServiceAccount;
  try {
    const decoded = atob(serviceAccountJsonB64);
    serviceAccount = JSON.parse(decoded);
  } catch {
    return jsonResponse({ error: 'FIREBASE_SERVICE_ACCOUNT_JSON_B64 is not valid base64-encoded JSON' }, 500);
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

  const translated = await runGoogleTranslation(serviceAccount, payload.text, payload.target_locale);
  if (translated === null) {
    return jsonResponse({ error: 'translation failed' }, 502);
  }

  return jsonResponse({ translated_text: translated }, 200);
});
