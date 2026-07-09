// design/system.md 6.2節「クイズ自動生成 + マルチエージェント検証パイプライン」に対応する
// Edge Function。Generator（1問生成）→Solver（同一問題を独立に3回解く）→Validator（採否判定）の
// 3段階マルチエージェントパイプラインを1回の呼び出しで実行し、`quiz_questions` に候補を記録する。
//
// - Gemini無料枠のレート制限（1分あたりのリクエスト数が少ない）を考慮し、1回の呼び出しで生成する
//   候補問題は1問のみとする（Generator 1回 + Solver 3回 + Validator 1回 = 計5回のGemini呼び出し）。
//   各呼び出しの間に約2秒のディレイを挟み、瞬間的なレート超過を避ける。
// - 全段階でモデルは `gemini-3-flash-preview`（軽量モデル）に統一する。Proモデルは使わない。
// - recalculate_scoresと同じ`X-Cron-Secret`パターンで保護する
//   （環境変数名: `QUIZ_GENERATION_CRON_SECRET`）。外部cron（GitHub Actions等）から定期HTTP呼び出しされる想定。
// - 採否ロジックはコード側で判定する（AIに丸投げしない）:
//     solver_agreement_rate >= 0.8 && validator.verdict === 'approved' の場合のみ
//     quiz_questions に is_active: true, validation_status: 'approved' でinsertする。
//     それ以外は is_active: false とし、validation_statusはvalidatorの判定
//     （'rejected' または 'human_review'）をそのまま使う（プールには出ないが記録は残す）。
// - いずれかの段階でGemini呼び出し失敗・JSONパース失敗した場合は、runをstatus: 'failed'で更新し、
//   例外を投げてクラッシュさせず200を返す（エラーはconsole.errorに残す）。

import { createClient } from 'jsr:@supabase/supabase-js@2';

const GEMINI_MODEL = 'gemini-3-flash-preview';
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const SOLVER_COUNT = 3;
const SOLVER_AGREEMENT_THRESHOLD = 0.8;
const INTER_CALL_DELAY_MS = 2000;

const QUESTION_TYPES = ['logic', 'geometry', 'current_events'] as const;
type QuestionType = typeof QUESTION_TYPES[number];

type GeneratorResult = {
  payload: { question: string; choices: string[] };
  correct_answer: string;
  time_limit_seconds: number;
  explanation: string;
};

type SolverResult = { answer: string };

type ValidatorResult = {
  verdict: 'approved' | 'rejected' | 'human_review';
  notes: string;
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function pickRandom<T>(items: readonly T[]): T {
  return items[Math.floor(Math.random() * items.length)];
}

function randomDifficulty(): number {
  return 1 + Math.floor(Math.random() * 5); // 1-5
}

// Geminiは`responseMimeType: 'application/json'`指定時でも、まれに有効なJSONオブジェクトの後に
// 余分なテキストを付け足すことがある（観測例: 問題文中の改行を含む長い出力の末尾に断片が付与される）。
// そのため単純なtrim/コードフェンス除去だけでなく、最初の`{`から対応する`}`までを
// 波括弧の深さを数えて抽出し、末尾の余分な文字列を切り捨てる。
function cleanJson(rawText: string): string {
  const stripped = rawText
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim();

  const start = stripped.indexOf('{');
  if (start === -1) return stripped;

  let depth = 0;
  let inString = false;
  let escapeNext = false;
  for (let i = start; i < stripped.length; i++) {
    const ch = stripped[i];
    if (escapeNext) {
      escapeNext = false;
      continue;
    }
    if (ch === '\\') {
      escapeNext = true;
      continue;
    }
    if (ch === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (ch === '{') depth++;
    if (ch === '}') {
      depth--;
      if (depth === 0) {
        return stripped.slice(start, i + 1);
      }
    }
  }
  // 対応する閉じ括弧が見つからなければ、そのままJSON.parseに渡してエラーとして扱う。
  return stripped;
}

// 直近のGemini呼び出し失敗理由。run失敗時にレスポンスへ含め、外部cron側のログで
// 原因（レート制限・一時的な過負荷503など）を切り分けられるようにする。
let lastGeminiError: string | null = null;

const GEMINI_MAX_ATTEMPTS = 3;
const GEMINI_RETRY_BASE_DELAY_MS = 3000;

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Gemini呼び出しの共通ヘルパー。`gemini-3-flash-preview`はプレビューモデルのため
// 「高負荷につき503」を一時的に返すことがある。429/503は指数バックオフで最大
// GEMINI_MAX_ATTEMPTS回までリトライし、それでも失敗したらnullを返す（呼び出し元でrun失敗として扱う）。
async function callGemini(prompt: string): Promise<string | null> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    lastGeminiError = 'GEMINI_API_KEY is not configured';
    console.error('generate_quiz_batch: GEMINI_API_KEY is not configured');
    return null;
  }

  for (let attempt = 1; attempt <= GEMINI_MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(`${GEMINI_ENDPOINT}?key=${apiKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0.7,
            responseMimeType: 'application/json',
          },
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        lastGeminiError = `HTTP ${response.status}: ${errorBody.slice(0, 500)}`;
        const retryable = response.status === 429 || response.status === 503;
        console.error(
          'generate_quiz_batch: Gemini API call failed',
          response.status,
          errorBody,
          retryable ? `(attempt ${attempt}/${GEMINI_MAX_ATTEMPTS}, will retry)` : '(not retryable)',
        );
        if (retryable && attempt < GEMINI_MAX_ATTEMPTS) {
          await sleepMs(GEMINI_RETRY_BASE_DELAY_MS * attempt);
          continue;
        }
        return null;
      }

      const json = await response.json();
      const rawText = json?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof rawText !== 'string') {
        lastGeminiError = `unexpected response shape: ${JSON.stringify(json).slice(0, 500)}`;
        console.error('generate_quiz_batch: unexpected Gemini response shape', json);
        return null;
      }
      return rawText;
    } catch (error) {
      lastGeminiError = `threw: ${String(error)}`;
      console.error('generate_quiz_batch: Gemini API call threw an error', error, `(attempt ${attempt}/${GEMINI_MAX_ATTEMPTS})`);
      if (attempt < GEMINI_MAX_ATTEMPTS) {
        await sleepMs(GEMINI_RETRY_BASE_DELAY_MS * attempt);
        continue;
      }
      return null;
    }
  }
  return null;
}

function buildGeneratorPrompt(questionType: QuestionType, difficulty: number, locale: string): string {
  return `あなたはIQテスト風クイズの出題者です。以下の条件で問題を1問作成してください。
- question_type: ${questionType}（logic=論理問題, geometry=図形・空間問題, current_events=時事問題）
- difficulty: ${difficulty}（1が最も易しく、5が最も難しい）
- locale: ${locale}（出題言語）
- 選択肢は4つ程度にしてください。

判定結果は必ず以下の厳密なJSON形式のみで返してください。説明文やMarkdownのコードフェンスは一切含めないでください:
{"payload": {"question": string, "choices": string[]}, "correct_answer": string, "time_limit_seconds": number, "explanation": string}

- correct_answerはchoicesの中のいずれか1つと完全に一致する文字列にしてください。
- time_limit_secondsは難易度に応じた妥当な制限時間（秒）にしてください。
- explanationには正解の簡潔な解説を含めてください。
`;
}

function buildSolverPrompt(question: string, choices: string[]): string {
  return `あなたはクイズの回答者です。以下の設問に対して、選択肢の中から最も正しいと思うものを1つ選んでください。

問題: ${question}
選択肢: ${choices.join(' / ')}

回答は必ず以下の厳密なJSON形式のみで返してください。説明文やMarkdownのコードフェンスは一切含めないでください:
{"answer": string}

- answerはchoicesの中のいずれか1つと完全に一致する文字列にしてください。
`;
}

function buildValidatorPrompt(
  question: string,
  choices: string[],
  correctAnswer: string,
  solverAnswers: string[],
): string {
  return `あなたはクイズ問題の品質検証者です。以下の設問・選択肢・想定正解・複数の回答者（Solver）の回答ログを確認し、
この問題をそのまま出題してよいか判定してください。曖昧さ、事実正確性、攻撃的表現の有無、難易度の妥当性、
（既存問題との類似は今回は判定不要）を簡易的にチェックしてください。

問題: ${question}
選択肢: ${choices.join(' / ')}
想定正解: ${correctAnswer}
Solverの回答ログ: ${JSON.stringify(solverAnswers)}

判定結果は必ず以下の厳密なJSON形式のみで返してください。説明文やMarkdownのコードフェンスは一切含めないでください:
{"verdict": "approved" | "rejected" | "human_review", "notes": string}
`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method not allowed' }), { status: 405 });
  }

  const cronSecret = Deno.env.get('QUIZ_GENERATION_CRON_SECRET');
  if (!cronSecret) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }
  const providedSecret = req.headers.get('X-Cron-Secret');
  if (providedSecret !== cronSecret) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: 'server misconfigured' }), { status: 500 });
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const questionType = pickRandom(QUESTION_TYPES);
  const difficulty = randomDifficulty();
  const locale = 'ja';

  // 1) runレコードをinsert
  const { data: run, error: runInsertError } = await supabase
    .from('quiz_generation_runs')
    .insert({
      question_type: questionType,
      locale,
      target_difficulty: difficulty,
      generator_model: GEMINI_MODEL,
      solver_models: [GEMINI_MODEL, GEMINI_MODEL, GEMINI_MODEL],
      validator_model: GEMINI_MODEL,
      status: 'running',
    })
    .select('id')
    .single();

  if (runInsertError || !run) {
    console.error('generate_quiz_batch: failed to insert quiz_generation_runs row', runInsertError);
    return new Response(JSON.stringify({ error: 'failed to create run' }), { status: 500 });
  }
  const runId: string = run.id;

  async function markRunFailed() {
    const { error } = await supabase
      .from('quiz_generation_runs')
      .update({ status: 'failed', completed_at: new Date().toISOString() })
      .eq('id', runId);
    if (error) {
      console.error('generate_quiz_batch: failed to mark run as failed', error);
    }
  }

  // 2) Generator
  const generatorRaw = await callGemini(buildGeneratorPrompt(questionType, difficulty, locale));
  if (generatorRaw === null) {
    console.error('generate_quiz_batch: generator call failed', runId);
    await markRunFailed();
    return new Response(
      JSON.stringify({ generated: false, approved: false, run_id: runId, debug_error: lastGeminiError }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  let generatorResult: GeneratorResult;
  try {
    const parsed = JSON.parse(cleanJson(generatorRaw));
    if (
      !parsed?.payload?.question ||
      !Array.isArray(parsed?.payload?.choices) ||
      typeof parsed?.correct_answer !== 'string' ||
      typeof parsed?.time_limit_seconds !== 'number' ||
      typeof parsed?.explanation !== 'string'
    ) {
      throw new Error('missing required fields');
    }
    generatorResult = parsed as GeneratorResult;
  } catch (error) {
    console.error('generate_quiz_batch: failed to parse generator response', error, generatorRaw);
    await markRunFailed();
    return new Response(
      JSON.stringify({
        generated: false,
        approved: false,
        run_id: runId,
        debug_error: `parse failed: ${String(error)}`,
        debug_raw: generatorRaw.slice(0, 500),
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  await sleep(INTER_CALL_DELAY_MS);

  // 3) Solver x3（独立に、正解は渡さず解かせる）
  const solverAnswers: string[] = [];
  for (let i = 0; i < SOLVER_COUNT; i++) {
    const solverRaw = await callGemini(
      buildSolverPrompt(generatorResult.payload.question, generatorResult.payload.choices),
    );
    if (solverRaw === null) {
      console.error('generate_quiz_batch: solver call failed', runId, i);
      await markRunFailed();
      return new Response(
        JSON.stringify({ generated: true, approved: false, run_id: runId, stage: `solver_${i}_call`, debug_error: lastGeminiError }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }
    try {
      const parsed = JSON.parse(cleanJson(solverRaw)) as SolverResult;
      if (typeof parsed?.answer !== 'string') throw new Error('missing answer field');
      solverAnswers.push(parsed.answer);
    } catch (error) {
      console.error('generate_quiz_batch: failed to parse solver response', error, solverRaw);
      await markRunFailed();
      return new Response(
        JSON.stringify({
          generated: true,
          approved: false,
          run_id: runId,
          stage: `solver_${i}_parse`,
          debug_error: String(error),
          debug_raw: solverRaw.slice(0, 500),
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }
    if (i < SOLVER_COUNT - 1) {
      await sleep(INTER_CALL_DELAY_MS);
    }
  }

  // 4) solver_agreement_rate算出
  const agreementCount = solverAnswers.filter((a) => a === generatorResult.correct_answer).length;
  const solverAgreementRate = agreementCount / SOLVER_COUNT;

  await sleep(INTER_CALL_DELAY_MS);

  // 5) Validator
  const validatorRaw = await callGemini(
    buildValidatorPrompt(
      generatorResult.payload.question,
      generatorResult.payload.choices,
      generatorResult.correct_answer,
      solverAnswers,
    ),
  );
  if (validatorRaw === null) {
    console.error('generate_quiz_batch: validator call failed', runId);
    await markRunFailed();
    return new Response(
      JSON.stringify({ generated: true, approved: false, run_id: runId, stage: 'validator_call', debug_error: lastGeminiError }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  let validatorResult: ValidatorResult;
  try {
    const parsed = JSON.parse(cleanJson(validatorRaw));
    const verdict = parsed?.verdict;
    if (verdict !== 'approved' && verdict !== 'rejected' && verdict !== 'human_review') {
      throw new Error('invalid verdict value');
    }
    validatorResult = { verdict, notes: typeof parsed?.notes === 'string' ? parsed.notes : '' };
  } catch (error) {
    console.error('generate_quiz_batch: failed to parse validator response', error, validatorRaw);
    await markRunFailed();
    return new Response(
      JSON.stringify({
        generated: true,
        approved: false,
        run_id: runId,
        stage: 'validator_parse',
        debug_error: String(error),
        debug_raw: validatorRaw.slice(0, 500),
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 6) 採否ロジック（コード側で判定する）
  const approved = solverAgreementRate >= SOLVER_AGREEMENT_THRESHOLD && validatorResult.verdict === 'approved';
  const validationStatus = approved ? 'approved' : validatorResult.verdict;

  // lib/features/quiz/quiz_controller.dartのProviderは`kind`が
  // 'onboarding' | 'daily' | 'lock_quiz' のいずれかであることを前提にフィルタしているため、
  // 生成した問題を実際にアプリのプールへ供給するには、ここでこのいずれかを割り当てる必要がある
  // （それ以外の値を入れるとinsert自体は成功してもアプリ側からは一切参照されなくなる）。
  // デイリーミッションのプール補充を主目的とするため、既定は'daily'とする。
  const KIND = 'daily';

  const { error: insertQuestionError } = await supabase.from('quiz_questions').insert({
    kind: KIND,
    question_type: questionType,
    locale,
    payload: generatorResult.payload,
    correct_answer: generatorResult.correct_answer,
    difficulty: Math.round(difficulty),
    time_limit_seconds: Math.round(generatorResult.time_limit_seconds),
    is_active: approved,
    generated_by: 'gemini',
    generation_run_id: runId,
    validation_status: validationStatus,
    solver_agreement_rate: solverAgreementRate,
    validator_notes: validatorResult.notes,
  });

  if (insertQuestionError) {
    console.error('generate_quiz_batch: failed to insert quiz_questions row', insertQuestionError);
    await markRunFailed();
    return new Response(
      JSON.stringify({
        generated: true,
        approved: false,
        run_id: runId,
        insert_error: insertQuestionError.message,
        insert_error_details: insertQuestionError.details,
        insert_error_hint: insertQuestionError.hint,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 7) runレコードを更新
  const { error: runUpdateError } = await supabase
    .from('quiz_generation_runs')
    .update({
      candidates_generated: 1,
      candidates_approved: approved ? 1 : 0,
      status: 'completed',
      completed_at: new Date().toISOString(),
    })
    .eq('id', runId);

  if (runUpdateError) {
    console.error('generate_quiz_batch: failed to update quiz_generation_runs row', runUpdateError);
  }

  return new Response(
    JSON.stringify({
      generated: true,
      approved,
      run_id: runId,
      solver_agreement_rate: solverAgreementRate,
      validator_verdict: validatorResult.verdict,
      validator_notes: validatorResult.notes,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
