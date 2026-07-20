-- design/product.md 5章「多言語対応」: quiz_questionsは既にlocale列を持つが、
-- 既存シードは全て'ja'のみだったため、アプリ側でロケールに応じた出し分けをしても
-- 英語ユーザーには問題が出題できなかった。既存10問（onboarding4問/daily6問）の
-- 英訳版を'en'として追加する（内容は日本語版と等価）。

insert into public.quiz_questions
  (kind, question_type, locale, payload, correct_answer, difficulty, time_limit_seconds, is_active, generated_by, validation_status)
values
  ('onboarding', 'logic', 'en',
   '{"question": "If A is greater than B, and B is greater than C, what is the relationship between A and C?", "choices": ["A is greater than C", "A is less than C", "A equals C", "Cannot be determined"]}',
   'A is greater than C', 1, 15, true, 'human', 'approved'),
  ('onboarding', 'geometry', 'en',
   '{"question": "What is the sum of the interior angles of an equilateral triangle?", "choices": ["180", "360", "270", "90"]}',
   '180', 1, 15, true, 'human', 'approved'),
  ('onboarding', 'logic', 'en',
   '{"question": "Which is the best counterexample to the claim \"All birds can fly\"?", "choices": ["Penguin", "Sparrow", "Pigeon", "Swallow"]}',
   'Penguin', 1, 15, true, 'human', 'approved'),
  ('onboarding', 'current_events', 'en',
   '{"question": "How many days are there in a non-leap year?", "choices": ["365", "364", "366", "360"]}',
   '365', 1, 15, true, 'human', 'approved'),
  ('daily', 'logic', 'en',
   '{"question": "In a round-robin tournament with 5 players where each pair plays once, how many matches are there in total?", "choices": ["10", "20", "15", "25"]}',
   '10', 2, 15, true, 'human', 'approved'),
  ('daily', 'geometry', 'en',
   '{"question": "If a circle has a diameter of 10cm, what is its radius in cm?", "choices": ["5", "10", "20", "2.5"]}',
   '5', 1, 15, true, 'human', 'approved'),
  ('daily', 'logic', 'en',
   '{"question": "If \"if it rains, the ground gets wet\" is true, which of the following is NOT necessarily true?", "choices": ["If the ground is not wet, it did not rain", "If it did not rain, the ground is not wet", "If the ground is wet, it rained", "If it rains, the ground gets wet"]}',
   'If it did not rain, the ground is not wet', 2, 15, true, 'human', 'approved'),
  ('daily', 'current_events', 'en',
   '{"question": "How many days are there in a week?", "choices": ["7", "5", "10", "6"]}',
   '7', 1, 15, true, 'human', 'approved'),
  ('daily', 'geometry', 'en',
   '{"question": "If a square has a side length of 4cm, what is its area in square cm?", "choices": ["16", "8", "12", "20"]}',
   '16', 1, 15, true, 'human', 'approved'),
  ('daily', 'logic', 'en',
   '{"question": "What number comes next in the sequence 3, 6, 9, 12?", "choices": ["15", "14", "16", "18"]}',
   '15', 1, 15, true, 'human', 'approved');
