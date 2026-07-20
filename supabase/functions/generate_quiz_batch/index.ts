// design/system.md 6.2節「クイズ自動生成 + マルチエージェント検証パイプライン」に対応する
// Edge Function。Generator（N問まとめて生成）→Solver（同じN問を独立に3回解く）→Validator（N問まとめて採否判定）の
// 3段階マルチエージェントパイプラインを1回の呼び出しで実行し、`quiz_questions` に候補を記録する。
//
// - 効率のため1問ずつではなく、1回の呼び出しでQUESTIONS_PER_BATCH問をまとめて生成・検証する
//   （Generator 1回 + Solver 3回 + Validator 1回 = 計5回のGemini呼び出しでN問分をまかなう）。
//   各呼び出しの間に約2秒のディレイを挟み、瞬間的なレート超過を避ける。
// - 全段階でモデルは `gemini-3.1-flash-lite`（軽量モデル）に統一する。Proモデルは使わない。
// - recalculate_scoresと同じ`X-Cron-Secret`パターンで保護する
//   （環境変数名: `QUIZ_GENERATION_CRON_SECRET`）。外部cron（GitHub Actions等）から定期HTTP呼び出しされる想定。
// - 採否ロジックはコード側で判定する（AIに丸投げしない）:
//     solver_agreement_rate >= 0.8 && validator.verdict === 'approved' の場合のみ
//     quiz_questions に is_active: true, validation_status: 'approved' でinsertする。
//     それ以外は is_active: false とし、validation_statusはvalidatorの判定
//     （'rejected' または 'human_review'）をそのまま使う（プールには出ないが記録は残す）。
//     問題ごとに個別に判定するため、バッチ内の一部だけ採用/不採用になることがある。
// - いずれかの段階でGemini呼び出し失敗・JSONパース失敗した場合は、runをstatus: 'failed'で更新し、
//   例外を投げてクラッシュさせず200を返す（エラーはconsole.errorに残す）。

import { createClient } from 'jsr:@supabase/supabase-js@2';

const GEMINI_MODEL = 'gemini-3.1-flash-lite';
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const QUESTIONS_PER_BATCH = 10;
const SOLVER_COUNT = 3;
const SOLVER_AGREEMENT_THRESHOLD = 0.8;
const INTER_CALL_DELAY_MS = 2000;

const QUESTION_TYPES = ['logic', 'geometry', 'current_events'] as const;
type QuestionType = typeof QUESTION_TYPES[number];

type GeneratorItem = {
  question_type: QuestionType;
  difficulty: number;
  payload: { question: string; choices: string[] };
  correct_answer: string;
  time_limit_seconds: number;
  explanation: string;
};

type SolverAnswer = { index: number; answer: string };

type ValidatorItem = {
  index: number;
  verdict: 'approved' | 'rejected' | 'human_review';
  notes: string;
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Geminiは`responseMimeType: 'application/json'`指定時でも、まれに有効なJSONオブジェクトの後に
// 余分なテキストを付け足すことがある（観測例: 問題文中の改行を含む長い出力の末尾に断片が付与される）。
// そのため単純なtrim/コードフェンス除去だけでなく、最初の`{`（または`[`）から対応する
// 閉じ括弧までを深さを数えて抽出し、末尾の余分な文字列を切り捨てる。
function cleanJson(rawText: string): string {
  const stripped = rawText
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim();

  const openChar = stripped[0] === '[' ? '[' : '{';
  const closeChar = openChar === '[' ? ']' : '}';
  const start = stripped.indexOf(openChar);
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
    if (ch === openChar) depth++;
    if (ch === closeChar) {
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

// Gemini呼び出しの共通ヘルパー。無料枠のレート制限（429）や一時的な過負荷（503）を
// 返すことがある。429/503は指数バックオフで最大
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

function buildGeneratorPrompt(count: number, locale: string): string {
  return `あなたはIQテスト風クイズの出題者です。以下の条件で問題を${count}問作成してください。
- 各問題は question_type（logic=論理問題, geometry=図形・空間問題, current_events=時事問題）を
  バランスよく混ぜてください。
- 各問題の difficulty は1〜5の範囲でバランスよく混ぜてください（1が最も易しく、5が最も難しい）。
- locale: ${locale}（出題言語）
- 選択肢は4つ程度にしてください。
- ${count}問はすべて異なる内容にしてください（同工異曲の問題を作らないでください）。

判定結果は必ず以下の厳密なJSON形式のみで返してください。説明文やMarkdownのコードフェンスは一切含めないでください:
{"items": [{"question_type": string, "difficulty": number, "payload": {"question": string, "choices": string[]}, "correct_answer": string, "time_limit_seconds": number, "explanation": string}]}

- itemsはちょうど${count}件にしてください。
- correct_answerはそれぞれのchoicesの中のいずれか1つと完全に一致する文字列にしてください。
- time_limit_secondsは難易度に応じた妥当な制限時間（秒）にしてください。
- explanationには正解の簡潔な解説を含めてください。
`;
}

function buildSolverPrompt(items: GeneratorItem[]): string {
  const questionsText = items
    .map((item, index) => `[${index}] 問題: ${item.payload.question}\n選択肢: ${item.payload.choices.join(' / ')}`)
    .join('\n\n');

  return `あなたはクイズの回答者です。以下の${items.length}問それぞれについて、選択肢の中から最も正しいと思うものを1つ選んでください。

${questionsText}

回答は必ず以下の厳密なJSON形式のみで返してください。説明文やMarkdownのコードフェンスは一切含めないでください:
{"answers": [{"index": number, "answer": string}]}

- answersはちょうど${items.length}件、[]内のindex番号と対応させてください。
- answerはその問題のchoicesの中のいずれか1つと完全に一致する文字列にしてください。
`;
}

function buildValidatorPrompt(items: GeneratorItem[], solverRounds: SolverAnswer[][]): string {
  const questionsText = items
    .map((item, index) => {
      const answersForIndex = solverRounds.map((round) => round.find((a) => a.index === index)?.answer ?? null);
      return `[${index}] 問題: ${item.payload.question}\n選択肢: ${item.payload.choices.join(' / ')}\n想定正解: ${item.correct_answer}\nSolverの回答ログ: ${JSON.stringify(answersForIndex)}`;
    })
    .join('\n\n');

  return `あなたはクイズ問題の品質検証者です。以下の${items.length}問それぞれについて、設問・選択肢・想定正解・
複数の回答者（Solver）の回答ログを確認し、そのまま出題してよいか判定してください。曖昧さ、事実正確性、
攻撃的表現の有無、難易度の妥当性（既存問題との類似は今回は判定不要）を簡易的にチェックしてください。

${questionsText}

判定結果は必ず以下の厳密なJSON形式のみで返してください。説明文やMarkdownのコードフェンスは一切含めないでください:
{"items": [{"index": number, "verdict": "approved" | "rejected" | "human_review", "notes": string}]}

- itemsはちょうど${items.length}件、上記のindex番号と対応させてください。
`;
}

// lib/features/quiz/quiz_controller.dartのProviderは`kind`が
// 'onboarding' | 'daily' | 'lock_quiz' のいずれかであることを前提にフィルタしているため、
// 生成した問題を実際にアプリのプールへ供給するには、ここでこのいずれかを割り当てる必要がある
// （それ以外の値を入れるとinsert自体は成功してもアプリ側からは一切参照されなくなる）。
// デイリーミッションのプール補充を主目的とするため、既定は'daily'とする。
const KIND = 'daily';

// lib/features/quiz/quiz_controller.dartは表示言語（en/ja）でquiz_questions.localeを
// 絞り込むため、片方のlocaleしか生成し続けないともう片方のプールが枯渇し、デイリークイズの
// ランダム抽選が実質同じ問題を繰り返すだけになってしまう（実際に'ja'固定だったため
// 'en'側が6問のまま止まっていた不具合の修正）。
// quiz_generation_runsの直近のlocaleと逆を選ぶことで、外部cron側の設定を増やさずに
// 30分ごとの実行をen/ja交互に振り分ける。
const SUPPORTED_LOCALES = ['ja', 'en'] as const;

async function determineNextLocale(
  supabase: ReturnType<typeof createClient>,
): Promise<typeof SUPPORTED_LOCALES[number]> {
  const { data, error } = await supabase
    .from('quiz_generation_runs')
    .select('locale')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error('generate_quiz_batch: failed to look up last generation run locale', error);
  }

  const lastIndex = SUPPORTED_LOCALES.indexOf(data?.locale as typeof SUPPORTED_LOCALES[number]);
  return SUPPORTED_LOCALES[(lastIndex + 1) % SUPPORTED_LOCALES.length];
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

  const locale = await determineNextLocale(supabase);

  // 1) runレコードをinsert（バッチ全体で1レコード）
  const { data: run, error: runInsertError } = await supabase
    .from('quiz_generation_runs')
    .insert({
      question_type: 'mixed',
      locale,
      target_difficulty: 0,
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

  function fail(stage: string, extra: Record<string, unknown> = {}) {
    return new Response(
      JSON.stringify({ generated: false, approved_count: 0, run_id: runId, stage, ...extra }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 2) Generator（QUESTIONS_PER_BATCH問まとめて生成）
  const generatorRaw = await callGemini(buildGeneratorPrompt(QUESTIONS_PER_BATCH, locale));
  if (generatorRaw === null) {
    console.error('generate_quiz_batch: generator call failed', runId);
    await markRunFailed();
    return fail('generator_call', { debug_error: lastGeminiError });
  }

  let items: GeneratorItem[];
  try {
    const parsed = JSON.parse(cleanJson(generatorRaw));
    if (!Array.isArray(parsed?.items) || parsed.items.length === 0) {
      throw new Error('missing or empty items array');
    }
    items = (parsed.items as unknown[]).filter((raw): raw is GeneratorItem => {
      const item = raw as Partial<GeneratorItem>;
      return (
        !!item &&
        typeof item.payload?.question === 'string' &&
        Array.isArray(item.payload?.choices) &&
        typeof item.correct_answer === 'string' &&
        typeof item.time_limit_seconds === 'number' &&
        typeof item.explanation === 'string'
      );
    });
    if (items.length === 0) throw new Error('no valid items after filtering');
  } catch (error) {
    console.error('generate_quiz_batch: failed to parse generator response', error, generatorRaw);
    await markRunFailed();
    return fail('generator_parse', { debug_error: String(error), debug_raw: generatorRaw.slice(0, 800) });
  }

  await sleep(INTER_CALL_DELAY_MS);

  // 3) Solver x3（同じitems全体を、独立に3回解かせる。正解は渡さない）
  const solverRounds: SolverAnswer[][] = [];
  for (let round = 0; round < SOLVER_COUNT; round++) {
    const solverRaw = await callGemini(buildSolverPrompt(items));
    if (solverRaw === null) {
      console.error('generate_quiz_batch: solver call failed', runId, round);
      await markRunFailed();
      return fail(`solver_${round}_call`, { debug_error: lastGeminiError });
    }
    try {
      const parsed = JSON.parse(cleanJson(solverRaw));
      if (!Array.isArray(parsed?.answers)) throw new Error('missing answers array');
      const answers: SolverAnswer[] = parsed.answers.filter(
        (a: unknown): a is SolverAnswer =>
          !!a && typeof (a as SolverAnswer).index === 'number' && typeof (a as SolverAnswer).answer === 'string',
      );
      solverRounds.push(answers);
    } catch (error) {
      console.error('generate_quiz_batch: failed to parse solver response', error, solverRaw);
      await markRunFailed();
      return fail(`solver_${round}_parse`, { debug_error: String(error), debug_raw: solverRaw.slice(0, 800) });
    }
    if (round < SOLVER_COUNT - 1) {
      await sleep(INTER_CALL_DELAY_MS);
    }
  }

  await sleep(INTER_CALL_DELAY_MS);

  // 4) Validator（items全体をまとめて採否判定）
  const validatorRaw = await callGemini(buildValidatorPrompt(items, solverRounds));
  if (validatorRaw === null) {
    console.error('generate_quiz_batch: validator call failed', runId);
    await markRunFailed();
    return fail('validator_call', { debug_error: lastGeminiError });
  }

  let validatorItems: ValidatorItem[];
  try {
    const parsed = JSON.parse(cleanJson(validatorRaw));
    if (!Array.isArray(parsed?.items)) throw new Error('missing items array');
    validatorItems = parsed.items.filter((v: unknown): v is ValidatorItem => {
      const item = v as Partial<ValidatorItem>;
      return (
        !!item &&
        typeof item.index === 'number' &&
        (item.verdict === 'approved' || item.verdict === 'rejected' || item.verdict === 'human_review')
      );
    });
  } catch (error) {
    console.error('generate_quiz_batch: failed to parse validator response', error, validatorRaw);
    await markRunFailed();
    return fail('validator_parse', { debug_error: String(error), debug_raw: validatorRaw.slice(0, 800) });
  }

  // 5) 問題ごとに採否判定（コード側で判定する。AIに丸投げしない）＋insert
  let approvedCount = 0;
  let insertedCount = 0;
  const insertErrors: string[] = [];

  for (let index = 0; index < items.length; index++) {
    const item = items[index];
    const answersForIndex = solverRounds.map((round) => round.find((a) => a.index === index)?.answer ?? null);
    const agreementCount = answersForIndex.filter((a) => a === item.correct_answer).length;
    const solverAgreementRate = agreementCount / SOLVER_COUNT;

    const validatorItem = validatorItems.find((v) => v.index === index);
    const verdict = validatorItem?.verdict ?? 'human_review';
    const notes = validatorItem?.notes ?? '(validatorから対応する結果が得られませんでした)';

    const approved = solverAgreementRate >= SOLVER_AGREEMENT_THRESHOLD && verdict === 'approved';
    const validationStatus = approved ? 'approved' : verdict;
    if (approved) approvedCount++;

    const { error: insertQuestionError } = await supabase.from('quiz_questions').insert({
      kind: KIND,
      question_type: QUESTION_TYPES.includes(item.question_type) ? item.question_type : 'logic',
      locale,
      payload: item.payload,
      correct_answer: item.correct_answer,
      difficulty: Math.min(5, Math.max(1, Math.round(item.difficulty) || 1)),
      time_limit_seconds: Math.round(item.time_limit_seconds),
      is_active: approved,
      generated_by: 'gemini',
      generation_run_id: runId,
      validation_status: validationStatus,
      solver_agreement_rate: solverAgreementRate,
      validator_notes: notes,
    });

    if (insertQuestionError) {
      console.error('generate_quiz_batch: failed to insert quiz_questions row', index, insertQuestionError);
      insertErrors.push(`[${index}] ${insertQuestionError.message}`);
    } else {
      insertedCount++;
    }
  }

  // 6) runレコードを更新
  const { error: runUpdateError } = await supabase
    .from('quiz_generation_runs')
    .update({
      candidates_generated: insertedCount,
      candidates_approved: approvedCount,
      status: insertedCount > 0 ? 'completed' : 'failed',
      completed_at: new Date().toISOString(),
    })
    .eq('id', runId);

  if (runUpdateError) {
    console.error('generate_quiz_batch: failed to update quiz_generation_runs row', runUpdateError);
  }

  return new Response(
    JSON.stringify({
      generated: true,
      run_id: runId,
      candidates_generated: insertedCount,
      candidates_approved: approvedCount,
      insert_errors: insertErrors.length > 0 ? insertErrors : undefined,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
