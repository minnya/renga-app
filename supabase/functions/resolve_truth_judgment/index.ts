// design/system.md 7.1節「真偽投票フロー（実装レベル）」の締切精算バッチ。
//
// 本来は supabase/migrations/20260709150000_truth_judgment_system.sql 内の
// pg_cronスケジュール（5分毎）が public.resolve_truth_judgments() を定期実行する想定だが、
// recalculate_scores Edge Functionと同様、Supabase無料プランではpg_cron拡張が
// 利用できない場合があるため、その代替として外部cron（GitHub Actions等）から
// 一定間隔（5〜10分毎）でこのEdge FunctionをHTTP呼び出しすることで同等の締切精算を行う。

import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405 });
  }

  const cronSecret = Deno.env.get('RESOLVE_TRUTH_JUDGMENT_CRON_SECRET');
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

  const { error } = await supabase.rpc('resolve_truth_judgments');
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ resolved: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
