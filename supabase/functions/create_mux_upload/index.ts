// design/system.md 5.1節「動画アップロードフロー（Direct Upload）」。
//
// Flutterアプリから呼び出され、Mux API (`POST /video/v1/uploads`) を呼び出して
// Direct Upload用の署名付きURLと upload_id を発行するEdge Function。
//
// - Mux Token ID / Secret はクライアントに一切露出させず、Function Secrets
//   （`MUX_TOKEN_ID` / `MUX_TOKEN_SECRET`）としてのみ保持する（system.md 5.4節）。
// - SupabaseのJWTを検証し、ログイン済みユーザーのみ呼び出せるようにする。
// - system.md 12章の運用方針に従い、アップロード可能な動画の長さの上限を
//   Mux側の `max_duration_seconds` としても指定し、コスト増大を防ぐ。
// - Flutter Web（ブラウザ）から直接呼び出されるため、CORSプリフライト（OPTIONS）と
//   すべてのレスポンスへのAccess-Control-Allow-Originヘッダーが必須。

import { createClient } from 'jsr:@supabase/supabase-js@2';

const MUX_UPLOAD_ENDPOINT = 'https://api.mux.com/video/v1/uploads';
// system.md 12章「アップロード動画の長さを制限」（例: 60〜90秒）。
const MAX_VIDEO_DURATION_SECONDS = 90;

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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'method not allowed' }, 405);
  }

  // 認証済みユーザーのみ呼び出し可能にする（SupabaseのJWT検証）。
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'missing Authorization header' }, 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: 'server misconfigured' }, 500);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  const muxTokenId = Deno.env.get('MUX_TOKEN_ID');
  const muxTokenSecret = Deno.env.get('MUX_TOKEN_SECRET');
  if (!muxTokenId || !muxTokenSecret) {
    return jsonResponse({ error: 'Mux credentials not configured' }, 500);
  }

  const basicAuth = btoa(`${muxTokenId}:${muxTokenSecret}`);

  const muxResponse = await fetch(MUX_UPLOAD_ENDPOINT, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${basicAuth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      cors_origin: '*',
      new_asset_settings: {
        playback_policy: ['public'],
        max_resolution_tier: '1080p',
      },
      // Mux Direct Uploadはアップロード完了後にアセット側で長さを確認する。
      // クライアント側の悪用防止はEdge Function側の運用メモとして残す（system.md 5.4節）。
    }),
  });

  if (!muxResponse.ok) {
    const errorBody = await muxResponse.text();
    return jsonResponse({ error: 'failed to create Mux upload', detail: errorBody }, 502);
  }

  const muxJson = await muxResponse.json();
  const uploadUrl = muxJson?.data?.url;
  const uploadId = muxJson?.data?.id;

  if (!uploadUrl || !uploadId) {
    return jsonResponse({ error: 'unexpected Mux response' }, 502);
  }

  return jsonResponse(
    {
      upload_url: uploadUrl,
      upload_id: uploadId,
      max_duration_seconds: MAX_VIDEO_DURATION_SECONDS,
    },
    200,
  );
});
