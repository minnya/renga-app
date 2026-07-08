// design/system.md 2章「スコアリングロジック（Influence / Intellect）」・12章
// 「パーセンタイル（influence_percentile, intellect_percentile）は定期バッチ
// （Supabase Scheduled Function / pg_cron）で再計算し、profiles に反映するキャッシュ列とする」
// に対応するフォールバック用Edge Function。
//
// 本来はマイグレーション（20260708110000_add_score_recalculation_batch.sql）内の
// pg_cronスケジュールが public.recalculate_intellect_scores() / recalculate_influence_scores()
// を定期実行する想定だが、Supabase無料プランではpg_cron拡張が利用できない場合があるため、
// その代替として外部cron（GitHub Actions等のスケジュールジョブ）から一定間隔でこの
// Edge FunctionをHTTP呼び出しすることで同等の再計算を行えるようにする。
//
// - service roleキーでRPCを呼び出す（RLSに関係なく全ユーザーのスコアを再計算するバッチ処理のため）。
// - 外部から誰でも叩けるとDB負荷を増大させる無料枠リスクがあるため、
//   `RECALCULATE_SCORES_CRON_SECRET` による簡易な共有シークレット検証を行う
//   （mux_webhookの署名検証と同様、不正なリクエストは401で破棄する）。

import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405 });
  }

  const cronSecret = Deno.env.get('RECALCULATE_SCORES_CRON_SECRET');
  if (!cronSecret) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }

  const providedSecret = req.headers.get('X-Cron-Secret');
  if (providedSecret !== cronSecret) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { error: intellectError } = await supabase.rpc('recalculate_intellect_scores');
  if (intellectError) {
    return new Response(JSON.stringify({ error: intellectError.message }), { status: 500 });
  }

  const { error: influenceError } = await supabase.rpc('recalculate_influence_scores');
  if (influenceError) {
    return new Response(JSON.stringify({ error: influenceError.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ recalculated: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
