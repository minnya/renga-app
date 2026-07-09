-- design/system.md 1章・2章「平均値・日次推移（プロフィール画面の比較表示）」に対応する
-- マイグレーション。
--
-- これまで profiles.intellect_percentile / influence_percentile はユーザーごとの単一カラム
-- （キャッシュ値）のみが存在し、日付ごとの推移や全ユーザー平均を保持する仕組みが無かった。
-- 本マイグレーションでは以下を追加する。
--   1. user_score_history: ユーザー×日付ごとの intellect/influence スナップショット（推移グラフ・前日比用）
--   2. score_stats: 全ユーザー平均のキャッシュ（シングルトン行。平均比較表示用）
--   3. public.inverse_normal_cdf / public.intellect_iq_score:
--      lib/shared/iq_format.dart のIQ換算ロジック（Acklamの近似式）のSQL移植。
--      score_stats.avg_intellect_iq の算出に使用する。
--   4. public.recalculate_score_stats() / public.snapshot_daily_scores():
--      20260708110000_add_score_recalculation_batch.sql の
--      recalculate_intellect_scores()/recalculate_influence_scores() と同じスタイルの
--      SECURITY DEFINER関数。1日1回のpg_cronジョブとして追加登録する。

-- ─────────────────────────────
-- 1. user_score_history
-- ─────────────────────────────
create table public.user_score_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  snapshot_date date not null default current_date,
  intellect_score numeric not null default 0,
  intellect_percentile numeric not null default 0,
  influence_score numeric not null default 0,
  influence_percentile numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, snapshot_date)
);

create index user_score_history_user_id_snapshot_date_idx
  on public.user_score_history (user_id, snapshot_date);

alter table public.user_score_history enable row level security;

-- 他テーブル（profiles等）と同じ「公開読み取り可」パターン。書き込みはsnapshot_daily_scores()
-- （SECURITY DEFINER、テーブル所有者としてRLSをバイパス）経由のみを想定し、
-- 一般ユーザー向けのinsert/update/deleteポリシーは設けない。
create policy "user_score_history are publicly readable" on public.user_score_history for select using (true);

-- ─────────────────────────────
-- 2. score_stats（シングルトン）
-- ─────────────────────────────
create table public.score_stats (
  id boolean primary key default true,
  avg_intellect_iq numeric not null default 100,
  avg_influence_score numeric not null default 0,
  avg_influence_percentile numeric not null default 50,
  computed_at timestamptz not null default now(),
  constraint score_stats_singleton check (id)
);

insert into public.score_stats (id) values (true);

alter table public.score_stats enable row level security;

create policy "score_stats are publicly readable" on public.score_stats for select using (true);

-- ─────────────────────────────
-- 3. IQ換算ロジックのSQL移植（lib/shared/iq_format.dart と同一のAcklamの近似式）
-- ─────────────────────────────
create or replace function public.inverse_normal_cdf(p numeric)
returns numeric
language plpgsql
immutable
as $$
declare
  a numeric[] := array[
    -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
    1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00
  ];
  b numeric[] := array[
    -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
    6.680131188771972e+01, -1.328068155288572e+01
  ];
  c numeric[] := array[
    -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
    -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00
  ];
  d numeric[] := array[
    7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
    3.754408661907416e+00
  ];
  p_low constant numeric := 0.02425;
  p_high numeric;
  q numeric;
  r numeric;
begin
  p_high := 1 - p_low;

  if p < p_low then
    q := sqrt(-2 * ln(p));
    return (((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) * q + c[6])
      / ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1);
  elsif p <= p_high then
    q := p - 0.5;
    r := q * q;
    return (((((a[1] * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * r + a[6]) * q
      / (((((b[1] * r + b[2]) * r + b[3]) * r + b[4]) * r + b[5]) * r + 1);
  else
    q := sqrt(-2 * ln(1 - p));
    return -(((((c[1] * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) * q + c[6])
      / ((((d[1] * q + d[2]) * q + d[3]) * q + d[4]) * q + 1);
  end if;
end;
$$;

-- percentile（値が小さいほど上位、0-100）をIQスケール（平均100・標準偏差15）に変換する。
-- lib/shared/iq_format.dart の intellectIqScore() と同一のロジック。
create or replace function public.intellect_iq_score(percentile numeric)
returns numeric
language sql
immutable
as $$
  select 100 + 15 * public.inverse_normal_cdf(
    1 - (least(greatest(percentile, 0.1), 99.9) / 100)
  );
$$;

-- ─────────────────────────────
-- 4. 平均値キャッシュ再計算 / 日次スナップショット
-- ─────────────────────────────
-- 全ユーザーの現在の intellect_percentile / influence_score / influence_percentile から
-- 平均値を算出し score_stats（シングルトン行）へ反映する。
-- 20260708110000_add_score_recalculation_batch.sql の recalculate_intellect_scores() /
-- recalculate_influence_scores() の直後に呼び出す想定（最新のパーセンタイルを平均に反映するため）。
create or replace function public.recalculate_score_stats()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.score_stats
  set avg_intellect_iq = coalesce(stats.avg_intellect_iq, 100),
      avg_influence_score = coalesce(stats.avg_influence_score, 0),
      avg_influence_percentile = coalesce(stats.avg_influence_percentile, 50),
      computed_at = now()
  from (
    select
      avg(public.intellect_iq_score(intellect_percentile)) as avg_intellect_iq,
      avg(influence_score) as avg_influence_score,
      avg(influence_percentile) as avg_influence_percentile
    from public.profiles
  ) stats
  where score_stats.id = true;
end;
$$;

grant execute on function public.recalculate_score_stats() to service_role;

-- profiles の現在値（intellect_score/percentile, influence_score/percentile）を
-- 当日分の user_score_history 行としてupsertする（design/system.md 2章「日次推移」）。
-- 同日に複数回実行されても最新値で上書きされるだけで、行が重複することはない。
create or replace function public.snapshot_daily_scores()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.user_score_history (
    user_id, snapshot_date, intellect_score, intellect_percentile,
    influence_score, influence_percentile
  )
  select
    id, current_date, intellect_score, intellect_percentile,
    influence_score, influence_percentile
  from public.profiles
  on conflict (user_id, snapshot_date) do update
  set intellect_score = excluded.intellect_score,
      intellect_percentile = excluded.intellect_percentile,
      influence_score = excluded.influence_score,
      influence_percentile = excluded.influence_percentile;
end;
$$;

grant execute on function public.snapshot_daily_scores() to service_role;

-- ─────────────────────────────
-- pg_cron による日次実行
-- ─────────────────────────────
-- 20260708110000_add_score_recalculation_batch.sql と同じパターン。
-- パーセンタイル自体は既存の 'recalculate-scores' ジョブ（30分毎）で最新化されているため、
-- ここでは1日1回、その最新値をもとに平均値キャッシュと日次スナップショットのみを更新する。
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'daily-score-snapshot',
      '10 0 * * *',
      $cron$ select public.recalculate_score_stats(); select public.snapshot_daily_scores(); $cron$
    );
  else
    raise notice 'pg_cron extension not installed; skipping cron.schedule. Use a Scheduled Edge Function as a fallback scheduler instead.';
  end if;
exception when others then
  raise notice 'Failed to register pg_cron schedule (%). Use a Scheduled Edge Function as a fallback scheduler instead.', sqlerrm;
end;
$$;
