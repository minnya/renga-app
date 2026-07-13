-- design/product.md 3.4節の改訂に対応。
--
-- 1. 真偽審判リクエストをDiscover投稿限定からFeed/Discover両方の投稿へ解禁する。
--    Feed上でも「投稿者本人と同格以上の知能階層」の投票資格ルールはそのまま維持する。
-- 2. リクエスト起票者本人も、対象投稿の真偽投票に参加できるようにする（起票者自身は
--    Create権限保持者であることが起票の前提条件のため、他の投票者と同じ知能階層チェックを
--    一律に課すと、著者より知能階層が低い起票者が自分の起票した投票に参加できない事態が
--    起こりうる。起票者自身に限り、投稿者本人以上の知能階層チェックを免除する）。

-- ─────────────────────────────
-- truth_judgment_requests: insert RLSからcontext='discover'限定を撤廃
-- ─────────────────────────────
drop policy if exists "top intellect tier can insert truth_judgment_requests" on public.truth_judgment_requests;
create policy "top intellect tier can insert truth_judgment_requests" on public.truth_judgment_requests for insert
  with check (
    auth.uid() = requested_by
    and public.is_top_intellect_tier(auth.uid())
  );

-- ─────────────────────────────
-- request_truth_judgment: Feed/Discover両方の投稿を対象に許可
-- ─────────────────────────────
create or replace function public.request_truth_judgment(p_post_id uuid, p_window_hours int default 48, p_quorum int default 10)
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

-- ─────────────────────────────
-- cast_truth_vote: 起票者本人は投稿者本人以上の知能階層チェックを免除する
-- ─────────────────────────────
create or replace function public.cast_truth_vote(p_request_id uuid, p_verdict boolean)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_vote_id uuid;
  v_request record;
  v_post_author_id uuid;
  v_voter_percentile numeric;
  v_voter_tier text;
  v_ticket_count int;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;
  if not public.is_top_intellect_tier(v_user_id) then
    raise exception '真偽投票は上位25%%以上のユーザーのみ行えます';
  end if;

  select * into v_request from public.truth_judgment_requests where id = p_request_id for update;
  if v_request is null then
    raise exception '対象の真偽審判リクエストが見つかりません';
  end if;
  if v_request.status <> 'voting' or v_request.closes_at <= now() then
    raise exception 'この真偽審判リクエストは投票を締め切っています';
  end if;

  select author_id into v_post_author_id from public.posts where id = v_request.post_id;
  if v_user_id = v_post_author_id then
    raise exception '自分の投稿の真偽投票には投票できません';
  end if;

  select intellect_percentile into v_voter_percentile from public.profiles where id = v_user_id;

  -- 起票者本人はこの階層チェックを免除する（「審議ボタンを押した人自身も投票できる」要件）。
  if v_user_id <> v_request.requested_by
      and v_voter_percentile > v_request.author_intellect_percentile_snapshot then
    raise exception '投稿者本人と同格以上の知能階層のユーザーのみ投票できます';
  end if;

  v_voter_tier := case when v_voter_percentile <= 5 then 'top5' else 'top25' end;

  select ticket_count into v_ticket_count from public.user_assets where user_id = v_user_id for update;
  if v_ticket_count is null or v_ticket_count < 1 then
    raise exception '投票権チケットがありません。ショップでチケットを購入するか、デイリーボーナスをお待ちください';
  end if;

  update public.user_assets set ticket_count = ticket_count - 1, updated_at = now() where user_id = v_user_id;

  insert into public.truth_votes (request_id, user_id, verdict, voter_tier)
  values (p_request_id, v_user_id, p_verdict, v_voter_tier)
  returning id into v_vote_id;

  return v_vote_id;
end;
$$;
