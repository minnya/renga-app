-- design/product.md 2.1節「画面別の権限モデル（Read / Create）」・3.4節「ステーキングと
-- ロジックチェック（Discover内・真偽投票）」・design/system.md 7章に対応。
--
-- 旧「Battle（挑戦投稿ペア＋観客ベット＋上位5%ジャッジによるlogic_verdicts）」の仕組みを廃止し、
-- 「Create権限保持者（上位25%%以上）によるオプトイン型の真偽投票（truth_judgment_requests /
-- truth_votes）」1本へ統合する。あわせてTP増減の監査元帳（tp_transactions）と、
-- Feed→Discoverキュレーション（discover_promotions）を追加する。

-- ─────────────────────────────
-- 旧Battle関連テーブルの削除
-- ─────────────────────────────
drop table if exists public.battle_bets;
drop table if exists public.battles;
drop table if exists public.logic_verdicts;

-- ─────────────────────────────
-- posts: 画面（コンテキスト）区分・真偽判定結果列の追加
-- ─────────────────────────────
alter table public.posts
  add column if not exists context text not null default 'feed', -- feed | discover（product.md 2.1節）
  add column if not exists truth_verdict boolean; -- null=未リクエスト/投票中/無効 | true | false（product.md 3.4節）

alter table public.posts drop column if exists broken_logic_score;

comment on column public.posts.post_type is 'normal | staked（旧battle_challengeは真偽投票への一本化に伴い廃止）';
comment on column public.posts.context is 'feed | discover。投稿がどの画面のCreate権限で作られたか（product.md 2.1節）';
comment on column public.posts.logic_verdict is 'unverified | endorsed。旧flagged_brokenは警告バッジ廃止に伴い削除（product.md 3.6節）';
comment on column public.posts.truth_verdict is '真偽審判リクエストの確定結果（product.md 3.4節、truth_judgment_requests参照）';

-- ─────────────────────────────
-- 上位ユーザー（Create権限）判定の共通ヘルパー（design/system.md 補足）
-- ─────────────────────────────
create or replace function public.is_top_intellect_tier(uid uuid)
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select coalesce(
    (select intellect_percentile <= 25 from public.profiles where id = uid),
    false
  );
$$;

grant execute on function public.is_top_intellect_tier(uuid) to authenticated, anon;

-- ─────────────────────────────
-- TP元帳（監査テーブル、product.md 3.4.1節）
-- ─────────────────────────────
create table public.tp_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  amount numeric not null, -- 正=獲得、負=消費/没収
  reason text not null,
  ref_type text, -- post | truth_judgment_request | truth_vote | discover_promotion 等
  ref_id uuid,
  balance_after numeric not null,
  created_at timestamptz not null default now()
);

create index tp_transactions_user_id_created_at_idx on public.tp_transactions (user_id, created_at desc);

alter table public.tp_transactions enable row level security;
create policy "users can read own tp_transactions" on public.tp_transactions for select using (auth.uid() = user_id);

-- ─────────────────────────────
-- Feed → Discoverキュレーション（product.md 3.5節）
-- ─────────────────────────────
create table public.discover_promotions (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  promoted_by uuid not null references public.profiles(id),
  tp_cost numeric not null,
  created_at timestamptz not null default now(),
  unique (post_id)
);

alter table public.discover_promotions enable row level security;
create policy "discover_promotions are publicly readable" on public.discover_promotions for select using (true);
create policy "top intellect tier can insert discover_promotions" on public.discover_promotions for insert
  with check (
    auth.uid() = promoted_by
    and public.is_top_intellect_tier(auth.uid())
    and exists (select 1 from public.posts p where p.id = post_id and p.context = 'feed')
  );

-- Feedの投稿をDiscoverへ引き上げつつ、対応するTP消費を単一トランザクションで行うRPC。
create or replace function public.promote_post_to_discover(p_post_id uuid, p_tp_cost numeric)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_balance numeric;
  v_promotion_id uuid;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;
  if not public.is_top_intellect_tier(v_user_id) then
    raise exception 'Discoverへの引き上げは上位25%%以上のユーザーのみ行えます';
  end if;
  if p_tp_cost is null or p_tp_cost <= 0 then
    raise exception 'TP消費量は1以上を指定してください';
  end if;
  if not exists (select 1 from public.posts where id = p_post_id and context = 'feed') then
    raise exception '対象投稿はFeedの投稿ではありません、またはすでにDiscoverへ引き上げ済みです';
  end if;

  select tp_balance into v_balance from public.profiles where id = v_user_id for update;
  if v_balance is null or v_balance < p_tp_cost then
    raise exception 'TP残高が不足しています';
  end if;

  update public.profiles set tp_balance = tp_balance - p_tp_cost where id = v_user_id;
  insert into public.tp_transactions (user_id, amount, reason, ref_type, ref_id, balance_after)
  values (v_user_id, -p_tp_cost, 'discover_promotion_cost', 'post', p_post_id, v_balance - p_tp_cost);

  insert into public.discover_promotions (post_id, promoted_by, tp_cost)
  values (p_post_id, v_user_id, p_tp_cost)
  returning id into v_promotion_id;

  return v_promotion_id;
end;
$$;

grant execute on function public.promote_post_to_discover(uuid, numeric) to authenticated;

-- Discover画面への新規投稿（Create権限保持者のみ、通常より高いTP消費、product.md 2.1節・3.4節）。
create or replace function public.create_discover_post(p_body text, p_staked_tp numeric)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_balance numeric;
  v_post_id uuid;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;
  if not public.is_top_intellect_tier(v_user_id) then
    raise exception 'Discoverへの新規投稿は上位25%%以上のユーザーのみ行えます';
  end if;
  if p_staked_tp is null or p_staked_tp <= 0 then
    raise exception '賭けるTPは1以上を指定してください';
  end if;
  if p_body is null or length(trim(p_body)) = 0 then
    raise exception '投稿内容を入力してください';
  end if;

  select tp_balance into v_balance from public.profiles where id = v_user_id for update;
  if v_balance is null or v_balance < p_staked_tp then
    raise exception 'TP残高が不足しています';
  end if;

  update public.profiles set tp_balance = tp_balance - p_staked_tp where id = v_user_id;
  insert into public.tp_transactions (user_id, amount, reason, ref_type, balance_after)
  values (v_user_id, -p_staked_tp, 'discover_post_cost', 'post', v_balance - p_staked_tp);

  insert into public.posts (author_id, body, media_type, post_type, staked_tp, context)
  values (v_user_id, trim(p_body), 'text', 'staked', p_staked_tp, 'discover')
  returning id into v_post_id;

  return v_post_id;
end;
$$;

grant execute on function public.create_discover_post(text, numeric) to authenticated;

-- ─────────────────────────────
-- 真偽審判リクエスト（product.md 3.4節、旧battles/battle_bets/logic_verdictsの後継）
-- ─────────────────────────────
create table public.truth_judgment_requests (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  requested_by uuid not null references public.profiles(id),
  author_intellect_percentile_snapshot numeric not null,
  status text not null default 'voting', -- voting | resolved | invalid
  resolved_verdict boolean,
  true_vote_count int not null default 0,
  false_vote_count int not null default 0,
  quorum_threshold int not null default 10,
  opens_at timestamptz not null default now(),
  closes_at timestamptz not null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (post_id)
);

alter table public.truth_judgment_requests enable row level security;
create policy "truth_judgment_requests are publicly readable" on public.truth_judgment_requests for select using (true);
create policy "top intellect tier can insert truth_judgment_requests" on public.truth_judgment_requests for insert
  with check (
    auth.uid() = requested_by
    and public.is_top_intellect_tier(auth.uid())
    and exists (select 1 from public.posts p where p.id = post_id and p.context = 'discover')
  );
-- update/deleteはEdge Function（service role）のみ（クライアント向けポリシーは設けない）。

-- 真偽投票（TPベット）
create table public.truth_votes (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.truth_judgment_requests(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  verdict boolean not null, -- true=本当, false=嘘
  staked_tp numeric not null,
  payout_tp numeric,
  created_at timestamptz not null default now(),
  unique (request_id, user_id)
);

alter table public.truth_votes enable row level security;
create policy "truth_votes are publicly readable" on public.truth_votes for select using (true);
-- insertはcast_truth_vote RPC（security definer）経由のみを正とする。テーブル直insertは
-- 条件(2)(投稿者本人以上の知能階層)・(4)(自己投票禁止)のような投稿横断の検証をRLSのみで
-- 完結させにくいため、RPC内で全条件を検証してinsertする方式に寄せる（update/deleteは不可）。

-- リクエスト起票（Create権限保持者のみ、対象postがcontext='discover'であること前提）。
create or replace function public.request_truth_judgment(p_post_id uuid, p_window_hours int default 48, p_quorum int default 10)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_author_id uuid;
  v_post_context text;
  v_author_percentile numeric;
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;
  if not public.is_top_intellect_tier(v_user_id) then
    raise exception '真偽審判リクエストは上位25%%以上のユーザーのみ起票できます';
  end if;

  select author_id, context into v_author_id, v_post_context from public.posts where id = p_post_id;
  if v_author_id is null then
    raise exception '対象投稿が見つかりません';
  end if;
  if v_post_context <> 'discover' then
    raise exception 'Discoverの投稿にのみ真偽審判リクエストを起票できます';
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

grant execute on function public.request_truth_judgment(uuid, int, int) to authenticated;

-- 真偽投票（TP減算＋truth_votes insertをアトミックに実行）。
create or replace function public.cast_truth_vote(p_request_id uuid, p_verdict boolean, p_staked_tp numeric)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_balance numeric;
  v_vote_id uuid;
  v_request record;
  v_post_author_id uuid;
  v_voter_percentile numeric;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;
  if p_staked_tp is null or p_staked_tp <= 0 then
    raise exception '賭けるTPは1以上を指定してください';
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
  if v_voter_percentile > v_request.author_intellect_percentile_snapshot then
    raise exception '投稿者本人と同格以上の知能階層のユーザーのみ投票できます';
  end if;

  select tp_balance into v_balance from public.profiles where id = v_user_id for update;
  if v_balance is null or v_balance < p_staked_tp then
    raise exception 'TP残高が不足しています';
  end if;

  update public.profiles set tp_balance = tp_balance - p_staked_tp where id = v_user_id;
  insert into public.tp_transactions (user_id, amount, reason, ref_type, ref_id, balance_after)
  values (v_user_id, -p_staked_tp, 'truth_vote_stake', 'truth_judgment_request', p_request_id, v_balance - p_staked_tp);

  insert into public.truth_votes (request_id, user_id, verdict, staked_tp)
  values (p_request_id, v_user_id, p_verdict, p_staked_tp)
  returning id into v_vote_id;

  return v_vote_id;
end;
$$;

grant execute on function public.cast_truth_vote(uuid, boolean, numeric) to authenticated;

-- 締切精算（Scheduled Function経由。resolve_truth_judgment Edge Functionから
-- service roleでの呼び出しを想定、design/system.md 7.1節参照）。
create or replace function public.resolve_truth_judgments()
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  v_true_count int;
  v_false_count int;
  v_total int;
  v_verdict boolean;
begin
  for r in
    select * from public.truth_judgment_requests
    where status = 'voting' and closes_at <= now()
    for update skip locked
  loop
    select
      count(*) filter (where verdict = true),
      count(*) filter (where verdict = false)
    into v_true_count, v_false_count
    from public.truth_votes
    where request_id = r.id;

    v_total := v_true_count + v_false_count;

    if v_total < r.quorum_threshold then
      -- クォーラム未達: 無効化し、全投票者へstaked_tpをそのまま返還する。
      update public.truth_judgment_requests
      set status = 'invalid', resolved_verdict = null, resolved_at = now(),
          true_vote_count = v_true_count, false_vote_count = v_false_count
      where id = r.id;

      update public.profiles pr
      set tp_balance = pr.tp_balance + tv.staked_tp
      from public.truth_votes tv
      where tv.request_id = r.id and tv.user_id = pr.id;

      insert into public.tp_transactions (user_id, amount, reason, ref_type, ref_id, balance_after)
      select tv.user_id, tv.staked_tp, 'truth_vote_refund', 'truth_vote', tv.id, pr.tp_balance
      from public.truth_votes tv
      join public.profiles pr on pr.id = tv.user_id
      where tv.request_id = r.id;
    else
      v_verdict := v_true_count > v_false_count;

      update public.truth_judgment_requests
      set status = 'resolved', resolved_verdict = v_verdict, resolved_at = now(),
          true_vote_count = v_true_count, false_vote_count = v_false_count
      where id = r.id;

      update public.posts set truth_verdict = v_verdict where id = r.post_id;

      -- 的中側: プラットフォーム負担で2倍配当（原資は敗者没収分と紐付けない、product.md 3.4節）。
      update public.profiles pr
      set tp_balance = pr.tp_balance + tv.staked_tp * 2
      from public.truth_votes tv
      where tv.request_id = r.id and tv.user_id = pr.id and tv.verdict = v_verdict;

      insert into public.tp_transactions (user_id, amount, reason, ref_type, ref_id, balance_after)
      select tv.user_id, tv.staked_tp * 2, 'truth_vote_payout', 'truth_vote', tv.id, pr.tp_balance
      from public.truth_votes tv
      join public.profiles pr on pr.id = tv.user_id
      where tv.request_id = r.id and tv.verdict = v_verdict;

      update public.truth_votes set payout_tp = staked_tp * 2 where request_id = r.id and verdict = v_verdict;
      update public.truth_votes set payout_tp = 0 where request_id = r.id and verdict <> v_verdict;

      -- 外れ側: 追加処理なし（stake時点で既に減算済み＝没収）。監査ログのみ残す。
      insert into public.tp_transactions (user_id, amount, reason, ref_type, ref_id, balance_after)
      select tv.user_id, 0, 'truth_vote_forfeit', 'truth_vote', tv.id, pr.tp_balance
      from public.truth_votes tv
      join public.profiles pr on pr.id = tv.user_id
      where tv.request_id = r.id and tv.verdict <> v_verdict;

      -- ストライク: 偽確定時、投稿者にstrikesレコードを追加する（design/system.md 7.2節）。
      if v_verdict = false then
        insert into public.strikes (user_id, strike_number, reason_request_id)
        select p.author_id,
               coalesce((select max(strike_number) from public.strikes s where s.user_id = p.author_id), 0) + 1,
               r.id
        from public.posts p where p.id = r.post_id;
      end if;
    end if;
  end loop;
end;
$$;

grant execute on function public.resolve_truth_judgments() to service_role;

-- ─────────────────────────────
-- strikes: reason_post_id → reason_request_id への統合
-- ─────────────────────────────
alter table public.strikes add column if not exists reason_request_id uuid references public.truth_judgment_requests(id);
alter table public.strikes drop column if exists reason_post_id;

-- appeals.target_typeは 'verdict'|'strike' から 'truth_judgment'|'strike' に意味変更（列自体はtextのまま）。
comment on column public.appeals.target_type is 'truth_judgment | strike';

-- ─────────────────────────────
-- Intellect Score再計算バッチの参照先をbattles/logic_verdictsからtruth_votes/
-- truth_judgment_requestsへ更新する（design/system.md 2章「Intellect Score」）。
-- ─────────────────────────────
create or replace function public.recalculate_intellect_scores()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  with quiz_stats as (
    select
      qr.user_id,
      avg(
        case when qr.is_correct
          then greatest(0, 1 - (qr.response_time_ms::numeric / greatest(qq.time_limit_seconds * 1000, 1)))
          else 0
        end
      ) as accuracy_speed_factor
    from public.quiz_responses qr
    join public.quiz_questions qq on qq.id = qr.question_id
    group by qr.user_id
  ),
  truth_win_counts as (
    -- 真偽投票で的中（多数決側に投票）した回数（design/system.md 2章「加点」）。
    select tv.user_id, count(*) as win_count
    from public.truth_votes tv
    join public.truth_judgment_requests r on r.id = tv.request_id
    where r.status = 'resolved' and tv.verdict = r.resolved_verdict
    group by tv.user_id
  ),
  endorse_counts as (
    select p.author_id as user_id, count(*) as endorse_count
    from public.endorsements e
    join public.posts p on p.id = e.post_id
    group by p.author_id
  ),
  false_verdict_counts as (
    -- 自分の投稿が真偽投票で「偽」確定した回数（design/system.md 2章「減点」）。
    select p.author_id as user_id, count(*) as false_count
    from public.truth_judgment_requests r
    join public.posts p on p.id = r.post_id
    where r.status = 'resolved' and r.resolved_verdict = false
    group by p.author_id
  )
  update public.profiles pr
  set intellect_score = greatest(
    0,
    coalesce(qs.accuracy_speed_factor, 0) * 100
      + coalesce(tw.win_count, 0) * 5
      + coalesce(ec.endorse_count, 0) * 2
      - coalesce(fc.false_count, 0) * 10
  )
  from public.profiles base
  left join quiz_stats qs on qs.user_id = base.id
  left join truth_win_counts tw on tw.user_id = base.id
  left join endorse_counts ec on ec.user_id = base.id
  left join false_verdict_counts fc on fc.user_id = base.id
  where pr.id = base.id;

  update public.profiles pr
  set intellect_percentile = ranked.percentile
  from (
    select id, percent_rank() over (order by intellect_score desc) * 100 as percentile
    from public.profiles
  ) ranked
  where pr.id = ranked.id;
end;
$$;

grant execute on function public.recalculate_intellect_scores() to service_role;

-- ─────────────────────────────
-- pg_cronによる締切精算の定期実行（利用不可環境ではフォールバックのEdge Functionで代替）
-- ─────────────────────────────
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'resolve-truth-judgments',
      '*/5 * * * *',
      $cron$ select public.resolve_truth_judgments(); $cron$
    );
  else
    raise notice 'pg_cron extension not installed; skipping cron.schedule. Use the resolve_truth_judgment Edge Function as a fallback scheduler instead.';
  end if;
exception when others then
  raise notice 'Failed to register pg_cron schedule (%). Use the resolve_truth_judgment Edge Function as a fallback scheduler instead.', sqlerrm;
end;
$$;
