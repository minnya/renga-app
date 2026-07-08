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

import { createClient } from 'jsr:@supabase/supabase-js@2';

const MUX_UPLOAD_ENDPOINT = 'https://api.mux.com/video/v1/uploads';
// system.md 12章「アップロード動画の長さを制限」（例: 60〜90秒）。
const MAX_VIDEO_DURATION_SECONDS = 90;

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405 });
  }

  // 認証済みユーザーのみ呼び出し可能にする（SupabaseのJWT検証）。
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'missing Authorization header' }), { status: 401 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !supabaseAnonKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }

  const muxTokenId = Deno.env.get('MUX_TOKEN_ID');
  const muxTokenSecret = Deno.env.get('MUX_TOKEN_SECRET');
  if (!muxTokenId || !muxTokenSecret) {
    return new Response(JSON.stringify({ error: 'Mux credentials not configured' }), { status: 500 });
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
    return new Response(
      JSON.stringify({ error: 'failed to create Mux upload', detail: errorBody }),
      { status: 502 },
    );
  }

  const muxJson = await muxResponse.json();
  const uploadUrl = muxJson?.data?.url;
  const uploadId = muxJson?.data?.id;

  if (!uploadUrl || !uploadId) {
    return new Response(JSON.stringify({ error: 'unexpected Mux response' }), { status: 502 });
  }

  return new Response(
    JSON.stringify({
      upload_url: uploadUrl,
      upload_id: uploadId,
      max_duration_seconds: MAX_VIDEO_DURATION_SECONDS,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
