-- design/product.md 3.4節・3.4.2節の改訂に対応: 真偽投票の締切を「24〜72時間」の幅から
-- 固定24時間に統一する。request_truth_judgment の p_window_hours 既定値のみを変更し、
-- 他の挙動（RLS・投票資格チェック等）は 20260709170000_truth_vote_feed_and_requester_vote.sql
-- から変更しない。

create or replace function public.request_truth_judgment(p_post_id uuid, p_window_hours int default 24, p_quorum int default 10)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_author_id uuid;
  v_author_percentile numeric;
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;
  if not public.is_top_intellect_tier(v_user_id) then
    raise exception '真偽審判リクエストは上位25%%以上のユーザーのみ起票できます';
  end if;

  select author_id into v_author_id from public.posts where id = p_post_id;
  if v_author_id is null then
    raise exception '対象投稿が見つかりません';
  end if;

  select intellect_percentile into v_author_percentile from public.profiles where id = v_author_id;

  insert into public.truth_judgment_requests
    (post_id, requested_by, author_intellect_percentile_snapshot, opens_at, closes_at, quorum_threshold)
  values
    (p_post_id, v_user_id, v_author_percentile, now(), now() + make_interval(hours => p_window_hours), p_quorum)
  returning id into v_request_id;

  return v_request_id;
end;
$$;
