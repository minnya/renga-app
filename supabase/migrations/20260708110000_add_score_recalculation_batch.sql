-- design/system.md 2章「スコアリングロジック（Influence / Intellect）」・12章
-- 「パーセンタイル（influence_percentile, intellect_percentile）は定期バッチ
-- （Supabase Scheduled Function / pg_cron）で再計算し、profiles に反映するキャッシュ列とする」
-- に対応するバッチ処理。
--
-- これまで profiles.influence_score/influence_percentile/intellect_score/intellect_percentile
-- カラムは存在するが実際に計算・更新する処理が存在せず、intellect_percentile が常に0のまま
-- （lib/features/feed/feed_controller.dart のコメント参照）で知能バッジ・レイヤーフィルターが
-- 機能しない状態だった。本マイグレーションでは、Phase1時点で実在するテーブル
-- （quiz_responses/quiz_questions/battles/endorsements/logic_verdicts/reposts/posts）のみを
-- 使ってスコアを算出するRPCを追加する。followers・impressionsに相当するテーブルは
-- Phase1範囲では未実装のため、design/system.mdの計算式には残しつつ値は0として組み込み、
-- 将来該当テーブルが追加された時点でそのカウントに差し替える前提とする。

-- ─────────────────────────────
-- Intellect Score / Percentile
-- ─────────────────────────────
-- design/system.md 2章「Intellect Score」:
--   基礎値: quiz_responses の正答率・回答速度から算出（速く正確なほど高評価）
--   加点: ロジックチェック勝利、専門家Endorse獲得
--   減点: logic_verdicts でbroken認定を受けた回数・重み
--   パーセンタイルへ変換し intellect_percentile に反映。
--
-- パーセンタイルの向きは「値が小さいほど上位」で統一する。
-- lib/features/feed/intellect_badge.dart の intellectBadgeTierOf() や
-- lib/features/feed/feed_controller.dart の
-- `p.authorIntellectPercentile <= 25` （上位25%）という既存実装の意味付けに合わせるため。
create or replace function public.recalculate_intellect_scores()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  -- 1) 基礎値＋加点／減点をまとめて intellect_score へ反映する。
  with quiz_stats as (
    -- 正答かつ制限時間に対して速いほど1に近づく係数（0〜1）の平均。
    -- 誤答は0として扱う（「速く正確なほど高評価」）。
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
  battle_win_rows as (
    -- ロジックチェック勝利（design/system.md 2章「加点: ロジックチェック勝利」）。
    -- challenger側勝利とdefender側（対象投稿の投稿者）勝利の両方を対象ユーザーへ寄せる。
    select challenger_id as user_id, count(*) as win_count
    from public.battles
    where status = 'resolved' and winner = 'challenger'
    group by challenger_id
    union all
    select p.author_id as user_id, count(*) as win_count
    from public.battles b
    join public.posts p on p.id = b.target_post_id
    where b.status = 'resolved' and b.winner = 'defender'
    group by p.author_id
  ),
  battle_win_counts as (
    select user_id, sum(win_count) as win_count
    from battle_win_rows
    group by user_id
  ),
  endorse_counts as (
    -- 専門家Endorse獲得（design/system.md 2章「加点: 専門家Endorse獲得」）。
    -- 誰がEndorseしたかの専門性重み付けはPhase1のendorsementsテーブルには無いため、
    -- 件数ベースの単純加点とする。
    select p.author_id as user_id, count(*) as endorse_count
    from public.endorsements e
    join public.posts p on p.id = e.post_id
    group by p.author_id
  ),
  broken_counts as (
    -- logic_verdicts でbroken認定を受けた回数（design/system.md 2章「減点」）。
    select p.author_id as user_id, count(*) as broken_count
    from public.logic_verdicts lv
    join public.posts p on p.id = lv.post_id
    where lv.verdict = 'broken'
    group by p.author_id
  )
  update public.profiles pr
  set intellect_score = greatest(
    0,
    coalesce(qs.accuracy_speed_factor, 0) * 100
      + coalesce(bw.win_count, 0) * 5
      + coalesce(ec.endorse_count, 0) * 2
      - coalesce(bc.broken_count, 0) * 10
  )
  from public.profiles base
  left join quiz_stats qs on qs.user_id = base.id
  left join battle_win_counts bw on bw.user_id = base.id
  left join endorse_counts ec on ec.user_id = base.id
  left join broken_counts bc on bc.user_id = base.id
  where pr.id = base.id;

  -- 2) 全ユーザー中のパーセンタイル順位へ変換する。
  -- percent_rank() はデフォルトで昇順（値が小さいほど0に近い）ため、
  -- 「値が大きいほど上位」であるintellect_scoreを降順で並べてpercent_rank()を取ることで、
  -- 最上位ユーザーが0（%）、最下位ユーザーが100（%）に近い値になるようにする
  -- （＝値が小さいほど上位、という既存コードの向きと一致）。
  update public.profiles pr
  set intellect_percentile = ranked.percentile
  from (
    select id, percent_rank() over (order by intellect_score desc) * 100 as percentile
    from public.profiles
  ) ranked
  where pr.id = ranked.id;
end;
$$;

-- Scheduled Function / pg_cron（service_role経由）からのみ呼び出す想定。
grant execute on function public.recalculate_intellect_scores() to service_role;

-- ─────────────────────────────
-- Influence Score / Percentile
-- ─────────────────────────────
-- design/system.md 2章「Influence Score」:
--   log(followers+1)*0.4 + log(reposts+1)*0.4 + log(impressions+1)*0.2 のような重み付き合成。
--
-- followers（フォロー関係）・impressions（表示回数）のテーブルはPhase1範囲では未実装のため、
-- 該当項目は0として式に組み込む（ln(0+1)=0）。将来 followers テーブル・インプレッション計測が
-- 追加された時点で、下記の 0 を実カウントの集計に差し替えること。
create or replace function public.recalculate_influence_scores()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  -- 1) 現状取得可能なデータ（リポスト数）のみで influence_score を算出する。
  with repost_counts as (
    select p.author_id as user_id, count(*) as repost_count
    from public.reposts r
    join public.posts p on p.id = r.post_id
    group by p.author_id
  )
  update public.profiles pr
  set influence_score =
    ln(0 + 1) * 0.4                                    -- followers: テーブル未実装のため0固定（将来followersテーブル追加時に反映）
      + ln(coalesce(rc.repost_count, 0) + 1) * 0.4      -- reposts: reposts テーブルから実カウント
      + ln(0 + 1) * 0.2                                 -- impressions: 計測未実装のため0固定（将来インプレッション計測実装時に反映）
  from public.profiles base
  left join repost_counts rc on rc.user_id = base.id
  where pr.id = base.id;

  -- 2) intellect と同じ向き（値が小さいほど上位）でパーセンタイルへ変換する。
  update public.profiles pr
  set influence_percentile = ranked.percentile
  from (
    select id, percent_rank() over (order by influence_score desc) * 100 as percentile
    from public.profiles
  ) ranked
  where pr.id = ranked.id;
end;
$$;

grant execute on function public.recalculate_influence_scores() to service_role;

-- ─────────────────────────────
-- pg_cron による定期実行
-- ─────────────────────────────
-- design/system.md 3章「pg_cron / Scheduled Functions: パーセンタイル再計算 ...」、12章
-- 「定期バッチ（Supabase Scheduled Function / pg_cron）で再計算」に対応。
--
-- Supabase無料プランではpg_cron拡張が利用できない場合がある。その場合は下記のDOブロックが
-- 例外を捕捉してスキップするため、マイグレーション自体は失敗しない。
-- pg_cronが利用不可の環境では、代わりに supabase/functions/recalculate_scores
-- （Supabase Scheduled Edge Function、または外部cron[GitHub Actions等]から定期的にHTTP呼び出し）
-- で同等の再計算を代替すること。
do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron extension is not available on this project (%). Use the recalculate_scores Edge Function as a fallback scheduler instead.', sqlerrm;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'recalculate-scores',
      '*/30 * * * *',
      $cron$ select public.recalculate_intellect_scores(); select public.recalculate_influence_scores(); $cron$
    );
  else
    raise notice 'pg_cron extension not installed; skipping cron.schedule. Use the recalculate_scores Edge Function as a fallback scheduler instead.';
  end if;
exception when others then
  raise notice 'Failed to register pg_cron schedule (%). Use the recalculate_scores Edge Function as a fallback scheduler instead.', sqlerrm;
end;
$$;
