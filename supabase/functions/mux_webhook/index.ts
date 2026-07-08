// design/system.md 5.1節「動画アップロードフロー（Direct Upload）」ステップ4。
//
// Mux Webhook（`video.asset.ready` 等）を受信し、署名検証（`Mux-Signature` ヘッダー）を
// 行ったうえで `videos` テーブルを更新するEdge Function。
//
// - このURLはインターネットに公開し、Mux Dashboardの Webhooks 設定に登録する（system.md 5.1節）。
// - 署名検証に失敗したリクエストは破棄する（system.md 5.4節）。
// - service role キーでDBを更新するため、RLSをバイパスして直接書き込む。

import { createClient } from 'jsr:@supabase/supabase-js@2';

// Muxの署名は `t=<timestamp>,v1=<hmac-sha256>` 形式で `Mux-Signature` ヘッダーに入る。
async function verifyMuxSignature(
  rawBody: string,
  signatureHeader: string | null,
  signingSecret: string,
): Promise<boolean> {
  if (!signatureHeader) return false;

  const parts = Object.fromEntries(
    signatureHeader.split(',').map((part) => {
      const [key, value] = part.split('=');
      return [key.trim(), value?.trim() ?? ''];
    }),
  );
  const timestamp = parts['t'];
  const expectedSignature = parts['v1'];
  if (!timestamp || !expectedSignature) return false;

  const signedPayload = `${timestamp}.${rawBody}`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(signingSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signatureBuffer = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signedPayload));
  const computedSignature = Array.from(new Uint8Array(signatureBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  return computedSignature === expectedSignature;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405 });
  }

  const signingSecret = Deno.env.get('MUX_WEBHOOK_SIGNING_SECRET');
  if (!signingSecret) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }

  const rawBody = await req.text();
  const signatureHeader = req.headers.get('Mux-Signature');
  const isValid = await verifyMuxSignature(rawBody, signatureHeader, signingSecret);
  if (!isValid) {
    return new Response(JSON.stringify({ error: 'invalid signature' }), { status: 401 });
  }

  const event = JSON.parse(rawBody);
  const eventType = event?.type as string | undefined;
  const uploadId = event?.data?.upload_id as string | undefined; // video.asset.* イベントに含まれる
  const assetId = event?.data?.id as string | undefined;

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  if (eventType === 'video.asset.ready') {
    const playbackIds = event?.data?.playback_ids as Array<{ id: string }> | undefined;
    const playbackId = playbackIds?.[0]?.id;
    const durationSeconds = event?.data?.duration as number | undefined;
    const thumbnailUrl = playbackId ? `https://image.mux.com/${playbackId}/thumbnail.jpg` : null;

    const { error } = await supabase
      .from('videos')
      .update({
        mux_asset_id: assetId,
        mux_playback_id: playbackId,
        duration_seconds: durationSeconds,
        thumbnail_url: thumbnailUrl,
        status: 'ready',
        updated_at: new Date().toISOString(),
      })
      .eq('mux_upload_id', uploadId);

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }
  } else if (eventType === 'video.asset.errored' || eventType === 'video.upload.errored') {
    const errorMessage = event?.data?.errors?.messages?.join(', ') ?? 'Mux processing failed';
    const { error } = await supabase
      .from('videos')
      .update({
        status: 'errored',
        error_message: errorMessage,
        updated_at: new Date().toISOString(),
      })
      .eq('mux_upload_id', uploadId);

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }
  } else if (eventType === 'video.asset.created' || eventType === 'video.upload.asset_created') {
    // トランスコード開始（processing）への遷移。ready/erroredより先に届く場合がある。
    const { error } = await supabase
      .from('videos')
      .update({ status: 'processing', updated_at: new Date().toISOString() })
      .eq('mux_upload_id', uploadId);

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }
  }
  // それ以外のイベント種別は無視する（system.mdで言及されていない付随イベント）。

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
