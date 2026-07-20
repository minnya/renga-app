-- 運用上の要件: Supabase Studio（Authentication > Users）からユーザーを削除した際、
-- 紐づく全レコードが連鎖削除されるようにする。
--
-- `profiles.id`は`auth.users(id) on delete cascade`済みだが、`profiles(id)`を参照する
-- 他テーブルの外部キーの多くは`on delete cascade`が付与されておらず、profiles行の削除時に
-- 外部キー制約違反でエラーとなっていた（結果としてauth.users側の削除もロールバックされる）。
-- 併せて、posts(id)を参照する一部テーブルにも同様の抜けがあり、
-- 「ユーザー削除→投稿削除」の連鎖が投稿配下のレコードで止まってしまうケースがあったため修正する。
--
-- 対象カラムの元の外部キー制約名はマイグレーション作成時に明示指定していない
-- （Postgresの自動命名に依存）ため、pg_constraintから実際の制約名を動的に取得して
-- drop・再作成する。resolved_by（通報を解決した運営者）・reason_post_id（ストライク理由の
-- 投稿、既に削除されている場合がある）はnullable列であり、削除で当該レコードごと消えるのは
-- 意図と異なるため`on delete set null`とする。それ以外のnot null列は`on delete cascade`とする。
do $$
declare
  r record;
  fk_name text;
begin
  for r in
    select * from (values
      ('posts', 'author_id', 'profiles', 'cascade'),
      ('videos', 'uploader_id', 'profiles', 'cascade'),
      ('reposts', 'post_id', 'posts', 'cascade'),
      ('reposts', 'user_id', 'profiles', 'cascade'),
      ('endorsements', 'post_id', 'posts', 'cascade'),
      ('endorsements', 'endorser_id', 'profiles', 'cascade'),
      ('domain_scores', 'user_id', 'profiles', 'cascade'),
      ('quiz_responses', 'user_id', 'profiles', 'cascade'),
      ('appeals', 'user_id', 'profiles', 'cascade'),
      ('reports', 'reporter_id', 'profiles', 'cascade'),
      ('reports', 'resolved_by', 'profiles', 'set null'),
      ('strikes', 'reason_post_id', 'posts', 'set null'),
      ('notifications', 'user_id', 'profiles', 'cascade'),
      ('tp_transactions', 'user_id', 'profiles', 'cascade'),
      ('discover_promotions', 'promoted_by', 'profiles', 'cascade'),
      ('truth_judgment_requests', 'requested_by', 'profiles', 'cascade'),
      ('truth_votes', 'user_id', 'profiles', 'cascade')
    ) as t(table_name, column_name, ref_table, on_delete_action)
  loop
    -- 対象カラムに現在張られている外部キー制約名を取得する（1カラム1FK前提）。
    select con.conname into fk_name
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    join pg_attribute att on att.attrelid = con.conrelid and att.attnum = any(con.conkey)
    where nsp.nspname = 'public'
      and rel.relname = r.table_name
      and con.contype = 'f'
      and att.attname = r.column_name
    limit 1;

    if fk_name is not null then
      execute format('alter table public.%I drop constraint %I', r.table_name, fk_name);
    end if;

    execute format(
      'alter table public.%I add constraint %I foreign key (%I) references public.%I(id) on delete %s',
      r.table_name,
      r.table_name || '_' || r.column_name || '_fkey',
      r.column_name,
      r.ref_table,
      r.on_delete_action
    );
  end loop;
end $$;
