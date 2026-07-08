// design/system.md 4章「通知アーキテクチャ」。
//
// FCM HTTP v1 APIを使ってプッシュ通知を送信するEdge Function。
//
// このFunction自体はイベント検知を行わない。呼び出し元
// （想定: Endorse insert / strike insert / battle resolved 等を検知する
// Database WebhooksやトリガーEdge Function）が、通知対象の user_id と
// 通知種別・内容を渡してこのFunctionを呼び出す想定。
//
// - 対象ユーザーの `profiles.locale`（既定: en）に応じて英語/日本語の
//   タイトル・本文を出し分ける（system.md 4章）。
// - 対象ユーザーの `device_tokens` を全件取得し、Firebase Admin SDKの
//   サービスアカウントJSON（Supabase Function Secrets `FIREBASE_SERVICE_ACCOUNT_JSON`）
//   を使ってGoogle OAuth2のアクセストークンを取得したうえで、
//   FCM HTTP v1 API (`https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`)
//   へ送信する。
// - 個々のトークンへの送信失敗（無効トークン等）はログに残すのみとし、
//   他のトークンへの送信や `notifications` テーブルへの保存処理は継続する。
// - 送信成功可否に関わらず、`notifications` テーブルへ通知レコードを保存する。

import { createClient } from 'jsr:@supabase/supabase-js@2';

interface SendPushNotificationPayload {
  user_id: string;
  notification_type: string; // notifications.kind: endorse_received | badge_unlocked | battle_resolved | strike_warning 等
  title_en: string;
  title_ja: string;
  body_en?: string;
  body_ja?: string;
  related_post_id?: string;
  data?: Record<string, string>; // ディープリンク解決用の追加ペイロード（go_routeのルートパス等）
}

interface FirebaseServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const GOOGLE_TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';

// PEM形式の秘密鍵をWeb Crypto APIで読み込めるバイナリ(ArrayBuffer)に変換する。
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

// サービスアカウントJSON（RS256秘密鍵）でJWTを自己署名し、
// Google OAuth2トークンエンドポイントでFCM送信用アクセストークンに交換する。
async function getFcmAccessToken(serviceAccount: FirebaseServiceAccount): Promise<string> {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claimSet = {
    iss: serviceAccount.client_email,
    scope: FCM_SCOPE,
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
    throw new Error(`failed to obtain FCM access token: ${errorBody}`);
  }

  const tokenJson = await tokenResponse.json();
  return tokenJson.access_token as string;
}

async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>,
): Promise<{ ok: boolean; error?: string }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          data: data ?? {},
        },
      }),
    },
  );

  if (!response.ok) {
    const errorBody = await response.text();
    return { ok: false, error: errorBody };
  }
  return { ok: true };
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405 });
  }

  let payload: SendPushNotificationPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid JSON body' }), { status: 400 });
  }

  const { user_id, notification_type, title_en, title_ja, body_en, body_ja, related_post_id, data } = payload;
  if (!user_id || !notification_type || !title_en || !title_ja) {
    return new Response(
      JSON.stringify({ error: 'user_id, notification_type, title_en, title_ja are required' }),
      { status: 400 },
    );
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!supabaseUrl || !serviceRoleKey || !serviceAccountJson) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }

  let serviceAccount: FirebaseServiceAccount;
  try {
    serviceAccount = JSON.parse(serviceAccountJson);
  } catch {
    return new Response(JSON.stringify({ error: 'FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON' }), {
      status: 500,
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // 対象ユーザーの locale（既定: en）を取得し、本文の言語を出し分ける（system.md 4章）。
  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('locale')
    .eq('id', user_id)
    .maybeSingle();

  if (profileError) {
    return new Response(JSON.stringify({ error: profileError.message }), { status: 500 });
  }

  const locale = profile?.locale === 'ja' ? 'ja' : 'en';
  const title = locale === 'ja' ? title_ja : title_en;
  const body = (locale === 'ja' ? body_ja : body_en) ?? '';

  // 対象ユーザーのdevice_tokensを全件取得する。
  const { data: deviceTokens, error: deviceTokensError } = await supabase
    .from('device_tokens')
    .select('fcm_token')
    .eq('user_id', user_id);

  if (deviceTokensError) {
    return new Response(JSON.stringify({ error: deviceTokensError.message }), { status: 500 });
  }

  const sendResults: Array<{ fcm_token: string; ok: boolean; error?: string }> = [];

  if (deviceTokens && deviceTokens.length > 0) {
    try {
      const accessToken = await getFcmAccessToken(serviceAccount);
      for (const { fcm_token } of deviceTokens) {
        try {
          const result = await sendFcmMessage(
            accessToken,
            serviceAccount.project_id,
            fcm_token,
            title,
            body,
            data,
          );
          sendResults.push({ fcm_token, ...result });
          if (!result.ok) {
            console.error(`FCM send failed for token ${fcm_token}: ${result.error}`);
          }
        } catch (err) {
          // 無効トークン等の個別失敗は全体を止めずログに残すのみ。
          console.error(`FCM send threw for token ${fcm_token}:`, err);
          sendResults.push({ fcm_token, ok: false, error: String(err) });
        }
      }
    } catch (err) {
      // アクセストークン取得自体の失敗は送信不能だが、notifications自体は保存を続行する。
      console.error('failed to obtain FCM access token:', err);
    }
  }

  // 送信成功可否に関わらずnotificationsテーブルへ記録する。
  const { error: insertError } = await supabase.from('notifications').insert({
    user_id,
    kind: notification_type,
    title,
    body,
    related_post_id: related_post_id ?? null,
  });

  if (insertError) {
    console.error('failed to insert notification record:', insertError);
  }

  return new Response(
    JSON.stringify({
      sent_count: sendResults.filter((r) => r.ok).length,
      failed_count: sendResults.filter((r) => !r.ok).length,
      results: sendResults,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
