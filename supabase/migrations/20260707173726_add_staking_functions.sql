-- design/product.md 3.4節「ステーキングとロジックチェック」＋3.2節「ロック解除クイズ（通行料）」用。
-- ステーキング投稿(post_type='staked')作成時にTP残高を検証・減算するRPCと、
-- ロック解除クイズ(kind='lock_quiz')のシードデータを追加する。

-- design/product.md 3.2節「ロック解除クイズ（通行料）: シリアス投稿(ステーキング・ツイート)時に
-- 1〜2問を義務化」用のシード問題（プール4問・使用2問）。既存のonboarding/dailyシードと同じ
-- パターン(design/system.md 6.2「初期実装時は手動で10問程度のシードクイズを投入する」)に倣う。
insert into public.quiz_questions
  (kind, question_type, locale, payload, correct_answer, difficulty, time_limit_seconds, is_active, generated_by, validation_status)
values
  ('lock_quiz', 'logic', 'ja',
   '{"question": "『すべてのAはBである』が真のとき、必ず真といえるのは?", "choices": ["AでないものはBでない", "BでないものはAでない", "BであるものはAである", "AであるものはBでない"]}',
   'BでないものはAでない', 2, 15, true, 'human', 'approved'),
  ('lock_quiz', 'geometry', 'ja',
   '{"question": "長方形の面積が24平方cmで縦が4cmのとき、横は何cm?", "choices": ["6", "8", "4", "12"]}',
   '6', 1, 15, true, 'human', 'approved'),
  ('lock_quiz', 'logic', 'ja',
   '{"question": "3人のうち少なくとも1人が嘘つきで、残り2人は正直者。Aが『私は嘘つきだ』と言った場合、Aは?", "choices": ["嘘つき", "正直者", "矛盾するため発言不可", "判定不能"]}',
   '矛盾するため発言不可', 3, 20, true, 'human', 'approved'),
  ('lock_quiz', 'current_events', 'ja',
   '{"question": "1時間は何分?", "choices": ["60", "100", "30", "90"]}',
   '60', 1, 15, true, 'human', 'approved');

-- design/product.md 3.4節「ステーキング・ツイート: 投稿時にTPを賭ける」用のアトミックRPC。
-- ロック解除クイズ通過後にクライアントから呼び出し、TP残高チェック→減算→posts insertを
-- 単一トランザクション内で行う（クライアント側での改ざん・競合を防ぐ、design/system.md 4章の
-- 「金銭・スコアに関わる信頼できる計算はサーバー側に必ず二重で持たせる」方針に準拠）。
-- auth.uid()を関数内で参照することで、呼び出し元が他人のTPを操作できないようにする。
create or replace function public.create_staked_post(p_body text, p_staked_tp numeric)
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

  insert into public.posts (author_id, body, media_type, post_type, staked_tp)
  values (v_user_id, trim(p_body), 'text', 'staked', p_staked_tp)
  returning id into v_post_id;

  return v_post_id;
end;
$$;

grant execute on function public.create_staked_post(text, numeric) to authenticated;
