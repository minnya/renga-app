-- design/product.md 3.2節「デイリーミッション: 1日3問。クリアでTP(Thought Power)とボーナスポイントを
-- 付与。連続日数ボーナスあり。」に対応。
-- これまでの increment_tp_balance(固定30 TP)は連続日数を考慮していなかったため、
-- profiles に連続達成日数を記録するカラムを追加し、TP付与と連続日数更新を単一トランザクションで
-- 行うRPCを新設する（design/system.md 4章「金銭・スコアに関わる信頼できる計算はサーバー側に
-- 必ず二重で持たせる」方針、及び20260707173724_seed_quiz_and_tp_function.sqlの
-- increment_tp_balance / 20260707173726_add_staking_functions.sqlの create_staked_post と
-- 同じ SECURITY DEFINER + auth.uid() 参照パターンに倣う）。

-- 現在の連続達成日数（当日分含む）。
alter table public.profiles
  add column daily_streak_count int not null default 0;

-- 最後にデイリーミッションを完了した日（UTC基準の日付）。
alter table public.profiles
  add column daily_streak_last_date date;

-- design/product.md 3.2節「デイリーミッション」用のアトミックRPC。
-- 呼び出しユーザー(auth.uid())の daily_streak_last_date を見て、
--   - 前回完了日が「昨日」(UTC基準) なら streak+1
--   - 前回完了日が「今日」なら、既に完了済みとして例外を送出し多重付与を防止する
--   - それ以外（空白期間、または初回）なら streak を 1 にリセット
-- ボーナスは既存の固定30 TP付与という設計を崩さない範囲で以下の通り単純化する:
--   - 3日連続ごとに +10 TP（例: 3, 6, 9日目...）
--   - 7日連続ごとに、上記に加えてさらに +30 TP（例: 7, 14日目...）
--   - 上記どちらにも該当しない日は基礎TPのみ
-- 戻り値として新しい連続日数・今回付与したTP・更新後のTP残高を返し、UI側でのフィードバック
-- 表示に利用できるようにする。
create or replace function public.award_daily_completion_tp(p_base_amount numeric default 30)
returns table (new_streak_count int, awarded_tp numeric, new_balance numeric)
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_prev_streak int;
  v_last_date date;
  v_today date := (now() at time zone 'utc')::date;
  v_new_streak int;
  v_bonus numeric := 0;
  v_total numeric;
  v_new_balance numeric;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;

  if p_base_amount is null or p_base_amount <= 0 then
    raise exception '基礎TPは1以上を指定してください';
  end if;

  select daily_streak_count, daily_streak_last_date
    into v_prev_streak, v_last_date
    from public.profiles
    where id = v_user_id
    for update;

  if v_last_date = v_today then
    -- 同日内の重複呼び出し（多重付与）を防止する。
    raise exception 'デイリーミッションは本日すでに達成済みです';
  elsif v_last_date = v_today - 1 then
    v_new_streak := coalesce(v_prev_streak, 0) + 1;
  else
    v_new_streak := 1;
  end if;

  if v_new_streak % 7 = 0 then
    v_bonus := 30;
  elsif v_new_streak % 3 = 0 then
    v_bonus := 10;
  else
    v_bonus := 0;
  end if;

  v_total := p_base_amount + v_bonus;

  update public.profiles
    set tp_balance = tp_balance + v_total,
        daily_streak_count = v_new_streak,
        daily_streak_last_date = v_today
    where id = v_user_id
    returning tp_balance into v_new_balance;

  return query select v_new_streak, v_total, v_new_balance;
end;
$$;

grant execute on function public.award_daily_completion_tp(numeric) to authenticated;
