// design/product.md 3.11節「Settings（設定）画面 / アカウント削除」・
// design/system.md 9章「設定・編集系UIの方針 / アカウント削除」。
//
// クライアントから`auth.users`を直接削除できない（サービスロールキーが必要）ため、
// このEdge Functionが呼び出し元のJWTを検証し、認証済みユーザー自身の`auth.users`行のみを
// サービスロールキーで削除する。`profiles`テーブルは`on delete cascade`で連動削除される。
//
// - クライアント側（`lib/features/settings/delete_account_page.dart`）は、削除前に
//   ユーザー名の再入力による確認ステップを必須としてから、この関数を呼び出す。
// - Flutter Web（ブラウザ）から直接呼び出される可能性があるため、CORSプリフライト（OPTIONS）と
//   すべてのレスポンスへのAccess-Control-Allow-Originヘッダーを付与する
//   （create_mux_uploadと同様のパターン）。
// - 認証には匿名キーのクライアントで呼び出し元のJWTを検証し、実際の削除操作のみ
//   サービスロールキーのクライアントで行う（他ユーザーのアカウントを削除できないようにするため）。

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
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
    return jsonResponse({ error: 'server misconfigured' }, 500);
  }

  // 呼び出し元のJWTを検証し、削除対象を「そのユーザー自身」に限定する。
  const anonClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await anonClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  const userId = userData.user.id;

  // 実際の削除操作はサービスロールキーで行う（`auth.users`の削除には管理者権限が必要）。
  const adminClient = createClient(supabaseUrl, serviceRoleKey);
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(userId);

  if (deleteError) {
    console.error('delete_account: failed to delete user', deleteError);
    return jsonResponse({ error: deleteError.message }, 500);
  }

  return jsonResponse({ success: true }, 200);
});
