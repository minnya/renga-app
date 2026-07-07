-- design/system.md 6.2「初期実装時は手動で10問程度のシードクイズを投入する」に沿った
-- オンボーディング(4問プール・3問使用)/デイリー(6問プール・3問使用)のシードデータ。
-- 自動生成パイプライン(Generator/Solver/Validator)はPhase3で別途実装する。

insert into public.quiz_questions
  (kind, question_type, locale, payload, correct_answer, difficulty, time_limit_seconds, is_active, generated_by, validation_status)
values
  ('onboarding', 'logic', 'ja',
   '{"question": "AがBより大きく、BがCより大きいとき、AとCの関係は?", "choices": ["AはCより大きい", "AはCより小さい", "AとCは等しい", "関係は決まらない"]}',
   'AはCより大きい', 1, 15, true, 'human', 'approved'),
  ('onboarding', 'geometry', 'ja',
   '{"question": "正三角形の内角の和は何度?", "choices": ["180", "360", "270", "90"]}',
   '180', 1, 15, true, 'human', 'approved'),
  ('onboarding', 'logic', 'ja',
   '{"question": "『すべての鳥は飛べる』という命題の反例として最も適切なのは?", "choices": ["ペンギン", "スズメ", "ハト", "ツバメ"]}',
   'ペンギン', 1, 15, true, 'human', 'approved'),
  ('onboarding', 'current_events', 'ja',
   '{"question": "1年は何日ですか?(うるう年を除く)", "choices": ["365", "364", "366", "360"]}',
   '365', 1, 15, true, 'human', 'approved'),
  ('daily', 'logic', 'ja',
   '{"question": "5人が総当たり戦を1回ずつ行うとき、試合数は合計何試合?", "choices": ["10", "20", "15", "25"]}',
   '10', 2, 15, true, 'human', 'approved'),
  ('daily', 'geometry', 'ja',
   '{"question": "円の直径が10cmのとき、半径は何cm?", "choices": ["5", "10", "20", "2.5"]}',
   '5', 1, 15, true, 'human', 'approved'),
  ('daily', 'logic', 'ja',
   '{"question": "『雨が降れば地面が濡れる』が真のとき、必ず真とは言えないのは?", "choices": ["地面が濡れていなければ雨は降っていない", "雨が降っていないなら地面は濡れていない", "地面が濡れているなら雨が降った", "雨が降れば地面は濡れる"]}',
   '雨が降っていないなら地面は濡れていない', 2, 15, true, 'human', 'approved'),
  ('daily', 'current_events', 'ja',
   '{"question": "1週間は何日?", "choices": ["7", "5", "10", "6"]}',
   '7', 1, 15, true, 'human', 'approved'),
  ('daily', 'geometry', 'ja',
   '{"question": "正方形の1辺が4cmのとき、面積は何平方cm?", "choices": ["16", "8", "12", "20"]}',
   '16', 1, 15, true, 'human', 'approved'),
  ('daily', 'logic', 'ja',
   '{"question": "3, 6, 9, 12の次に来る数は?", "choices": ["15", "14", "16", "18"]}',
   '15', 1, 15, true, 'human', 'approved');

-- design/product.md 3章「デイリーミッション: クリアでTPを付与」用の加算専用RPC。
-- auth.uid()を関数内で参照することで、呼び出し元が他人のTPを操作できないようにする。
create or replace function public.increment_tp_balance(p_amount numeric)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles set tp_balance = tp_balance + p_amount where id = auth.uid();
end;
$$;

grant execute on function public.increment_tp_balance(numeric) to authenticated;
