-- design/product.md 3.4.1〜3.4.5節・design/system.md 7章に対応。
--
-- 真偽投票をTP直接ステーク方式から「投票権チケット」仲介方式へ変更する。ストア審査ガイドライン
-- （賭博・リアルマネーギャンブル規制）対応のため、ユーザー間のTP直接移転を発生させず、
-- チケット購入・消費（ユーザー→プラットフォーム）と山分けボーナス新規発行（プラットフォーム→
-- ユーザー）の一方向フローのみで完結させる。
--
-- 実装上の簡略化: design/system.md 7章では`user_assets.tp_balance`への段階的一本化を書いたが、
-- 既存クライアントコード（プロフィール表示・各種RPC）が`profiles.tp_balance`を広く参照しているため、
-- TP残高は引き続き`profiles.tp_balance`を正とする。`user_assets`はチケット枚数・デイリー付与日のみを持つ。

-- ─────────────────────────────
-- user_assets: 投票権チケット枚数の管理
-- ─────────────────────────────
create table public.user_assets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  ticket_count int not null default 0,
  last_daily_ticket_granted_at date,
  updated_at timestamptz not null default now()
);

alter table public.user_assets enable row level security;
create policy "users can read own user_assets" on public.user_assets for select using (auth.uid() = user_id);

-- ─────────────────────────────
-- user_domain_scores: 投票ログ由来の「投稿しない隠れた賢者」ドメインスコア（product.md 3.4.1節）
-- ─────────────────────────────
create table public.user_domain_scores (
  user_id uuid not null references public.profiles(id) on delete cascade,
  domain text not null,
  correct_vote_streak int not null default 0,
  correct_vote_total int not null default 0,
  promoted_to_domain_expert boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, domain)
);

alter table public.user_domain_scores enable row level security;
create policy "user_domain_scores are publicly readable" on public.user_domain_scores for select using (true);

-- ─────────────────────────────
-- truth_votes: staked_tp（TP直接ステーク）を廃止し、voter_tierを追加
-- ─────────────────────────────
alter table public.truth_votes drop column if exists staked_tp;
alter table public.truth_votes add column if not exists voter_tier text; -- 'top5' | 'top25'（投票時点のintellect_percentileから判定。product.md 3.4.4節の2階建てメーター集計用）

update public.truth_votes set voter_tier = 'top25' where voter_tier is null;
alter table public.truth_votes alter column voter_tier set not null;

comment on column public.truth_votes.voter_tier is '投票時点のintellect_percentileから判定した階層。product.md 3.4.4節の2階建てメーター（Top5%/Top25%）集計に使用';
comment on column public.truth_votes.payout_tp is '確定後に反映。的中: product.md 3.4.3節の数理式に基づく山分けボーナスをtp_transactionsで別途新規発行。外れ: 0（チケットは全損）。無効: チケットのみ返還';

-- ─────────────────────────────
-- チケット購入（一般ユーザー向け。1枚=100TP、Remote Config `ticket_bulk_discount_tiers`は将来対応）
-- ─────────────────────────────
create or replace function public.purchase_tickets(p_ticket_count int)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_balance numeric;
  v_tp_cost numeric;
  v_new_ticket_count int;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;
  if p_ticket_count is null or p_ticket_count <= 0 then
    raise exception '購入枚数は1以上を指定してください';
  end if;

  v_tp_cost := p_ticket_count * 100;

  select tp_balance into v_balance from public.profiles where id = v_user_id for update;
  if v_balance is null or v_balance < v_tp_cost then
    raise exception 'TP残高が不足しています';
  end if;

  update public.profiles set tp_balance = tp_balance - v_tp_cost where id = v_user_id;
  insert into public.tp_transactions (user_id, amount, reason, ref_type, balance_after)
  values (v_user_id, -v_tp_cost, 'truth_vote_ticket_purchase', 'ticket', v_balance - v_tp_cost);

  insert into public.user_assets (user_id, ticket_count, updated_at)
  values (v_user_id, p_ticket_count, now())
  on conflict (user_id) do update
    set ticket_count = public.user_assets.ticket_count + excluded.ticket_count,
        updated_at = now()
  returning ticket_count into v_new_ticket_count;

  return v_new_ticket_count;
end;
$$;

grant execute on function public.purchase_tickets(int) to authenticated;

-- ─────────────────────────────
-- デイリー無料チケット付与（Top25%/Top5%特権。pg_cronで日次実行、service role専用）
-- ─────────────────────────────
create or replace function public.grant_daily_tickets()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.user_assets (user_id, ticket_count, last_daily_ticket_granted_at, updated_at)
  select pr.id, 3, current_date, now()
  from public.profiles pr
  where public.is_top_intellect_tier(pr.id)
  on conflict (user_id) do update
    set ticket_count = public.user_assets.ticket_count + 3,
        last_daily_ticket_granted_at = current_date,
        updated_at = now()
  where public.user_assets.last_daily_ticket_granted_at is distinct from current_date;
end;
$$;

grant execute on function public.grant_daily_tickets() to service_role;

-- ─────────────────────────────
-- 真偽投票（チケット1枚消費。TP増減は発生させない）
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
  if v_voter_percentile > v_request.author_intellect_percentile_snapshot then
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

grant execute on function public.cast_truth_vote(uuid, boolean) to authenticated;

-- ─────────────────────────────
-- 締切精算: チケット返還（無効時）／山分けボーナス新規発行（的中時）／ドメインスコア加算
-- ─────────────────────────────
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
  v_winner_count int;
  v_payout_per_winner numeric;
  v_post_domains text[];
  v_domain text;
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
      -- クォーラム未達: 無効化し、全投票者へ消費した投票権チケットを1枚返還する（TP増減は発生しない）。
      update public.truth_judgment_requests
      set status = 'invalid', resolved_verdict = null, resolved_at = now(),
          true_vote_count = v_true_count, false_vote_count = v_false_count
      where id = r.id;

      update public.user_assets ua
      set ticket_count = ua.ticket_count + 1, updated_at = now()
      from public.truth_votes tv
      where tv.request_id = r.id and tv.user_id = ua.user_id;
    else
      v_verdict := v_true_count > v_false_count;

      update public.truth_judgment_requests
      set status = 'resolved', resolved_verdict = v_verdict, resolved_at = now(),
          true_vote_count = v_true_count, false_vote_count = v_false_count
      where id = r.id;

      update public.posts set truth_verdict = v_verdict where id = r.post_id;

      -- 的中側: 山分けボーナス = (総チケット数 × 100TP) ÷ 正解者数。プラットフォームが新規発行し、
      -- 敗者が失うチケットとは会計上完全に切り離す（product.md 3.4.3節）。
      select count(*) into v_winner_count from public.truth_votes where request_id = r.id and verdict = v_verdict;
      if v_winner_count > 0 then
        v_payout_per_winner := (v_total * 100.0) / v_winner_count;

        update public.profiles pr
        set tp_balance = pr.tp_balance + v_payout_per_winner
        from public.truth_votes tv
        where tv.request_id = r.id and tv.user_id = pr.id and tv.verdict = v_verdict;

        insert into public.tp_transactions (user_id, amount, reason, ref_type, ref_id, balance_after)
        select tv.user_id, v_payout_per_winner, 'truth_vote_payout', 'truth_vote', tv.id, pr.tp_balance
        from public.truth_votes tv
        join public.profiles pr on pr.id = tv.user_id
        where tv.request_id = r.id and tv.verdict = v_verdict;

        update public.truth_votes set payout_tp = v_payout_per_winner where request_id = r.id and verdict = v_verdict;
      end if;

      -- 外れ側: 消費済みチケットは全損（返還なし）。TP増減が発生しないためtp_transactionsへの記録は行わない。
      update public.truth_votes set payout_tp = 0 where request_id = r.id and verdict <> v_verdict;

      -- ドメインスコア加算（product.md 3.4.1節「投稿しない隠れた賢者」の自動ドメイン抽出）。
      select p.domain_labels into v_post_domains from public.posts p where p.id = r.post_id;
      if v_post_domains is not null then
        foreach v_domain in array v_post_domains loop
          insert into public.user_domain_scores (user_id, domain, correct_vote_streak, correct_vote_total, updated_at)
          select tv.user_id, v_domain, 1, 1, now()
          from public.truth_votes tv
          where tv.request_id = r.id and tv.verdict = v_verdict
          on conflict (user_id, domain) do update
            set correct_vote_streak = public.user_domain_scores.correct_vote_streak + 1,
                correct_vote_total = public.user_domain_scores.correct_vote_total + 1,
                promoted_to_domain_expert = (public.user_domain_scores.correct_vote_streak + 1) >= 20,
                updated_at = now();
        end loop;
      end if;

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
-- pg_cronによるデイリーチケット付与の定期実行（利用不可環境ではフォールバックのEdge Functionで代替）
-- ─────────────────────────────
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'grant-daily-tickets',
      '0 0 * * *',
      $cron$ select public.grant_daily_tickets(); $cron$
    );
  else
    raise notice 'pg_cron extension not installed; skipping cron.schedule. Use a fallback Edge Function scheduler instead.';
  end if;
exception when others then
  raise notice 'Failed to register pg_cron schedule (%). Use a fallback Edge Function scheduler instead.', sqlerrm;
end;
$$;
