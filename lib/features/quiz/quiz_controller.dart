import 'dart:math';

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth_state.dart';
import '../../core/locale_controller.dart';
import '../../core/supabase_client.dart';
import '../../l10n/gen/app_localizations.dart';
import 'quiz_question.dart';

/// design/product.md 5章「多言語対応」: クイズ設問（`quiz_questions.locale`）を、
/// [localeProvider]で選択中の表示言語（未選択時は端末言語）に合わせて絞り込むための
/// ロケールコード。アプリがUIとして対応するロケール（[AppLocalizations.supportedLocales]）
/// 以外は既定言語の'en'にフォールバックする。
String _effectiveQuizLocale(Ref ref) {
  final override = ref.watch(localeProvider);
  final languageCode =
      override?.languageCode ?? WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  final supported = AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
  return supported.contains(languageCode) ? languageCode : 'en';
}

/// design/product.md 3.2節「ロック解除クイズ（通行料）」に対応する`lockQuiz`を追加。
/// TP消費投稿の直前に義務化される1〜2問のクイズ種別。
enum QuizKind { onboarding, daily, lockQuiz }

extension QuizKindX on QuizKind {
  String get value => switch (this) {
        QuizKind.onboarding => 'onboarding',
        QuizKind.daily => 'daily',
        QuizKind.lockQuiz => 'lock_quiz',
      };
}

/// [locale]の設問が1件もない場合は既定言語'en'にフォールバックして再取得する。
Future<List<Map<String, dynamic>>> _fetchQuizQuestions({
  required String kind,
  required String locale,
}) async {
  Future<List<Map<String, dynamic>>> query(String loc) => supabase
      .from('quiz_questions')
      .select()
      .eq('kind', kind)
      .eq('locale', loc)
      .eq('is_active', true);

  final rows = await query(locale);
  if (rows.isNotEmpty || locale == 'en') return rows;
  return query('en');
}

/// design/product.md 3章「オンボーディングクイズ: 初回登録時に3問」。
/// プールは4問用意し、先頭3問を使用する。
final onboardingQuestionsProvider = FutureProvider<List<QuizQuestion>>((ref) async {
  final locale = _effectiveQuizLocale(ref);
  final rows = await _fetchQuizQuestions(kind: 'onboarding', locale: locale);
  rows.sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String));
  return rows.take(3).map((row) => QuizQuestion.fromMap(row)).toList();
});

/// design/product.md 3章「デイリーミッション: 1日3問」。
/// プール(6問)からランダムに3問抽出する。
final dailyQuestionsProvider = FutureProvider.autoDispose<List<QuizQuestion>>((ref) async {
  final locale = _effectiveQuizLocale(ref);
  final rows = await _fetchQuizQuestions(kind: 'daily', locale: locale);
  final questions = rows.map((row) => QuizQuestion.fromMap(row)).toList();
  questions.shuffle(Random());
  return questions.take(3).toList();
});

/// design/product.md 3.2節「ロック解除クイズ（通行料）: TP消費投稿時に1〜2問を義務化」。
/// プール(4問)からランダムに2問抽出する。TP付与は行わず、通行料としての正誤判定のみに使う。
final lockQuizQuestionsProvider = FutureProvider.autoDispose<List<QuizQuestion>>((ref) async {
  final locale = _effectiveQuizLocale(ref);
  final rows = await _fetchQuizQuestions(kind: 'lock_quiz', locale: locale);
  final questions = rows.map((row) => QuizQuestion.fromMap(row)).toList();
  questions.shuffle(Random());
  return questions.take(2).toList();
});

/// 現在のユーザーがオンボーディングクイズに1問でも回答済みかどうか。
final hasCompletedOnboardingProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return false;

  final rows = await supabase
      .from('quiz_responses')
      .select('id, quiz_questions!inner(kind)')
      .eq('user_id', userId)
      .eq('quiz_questions.kind', 'onboarding')
      .limit(1);
  return rows.isNotEmpty;
});

/// 現在のユーザーが本日デイリークイズに回答済みかどうか（UTC日付の0時基準）。
///
/// サーバー側の`award_daily_completion_tp` RPC（達成済み判定・連続日数計算）はUTC日付
/// (`(now() at time zone 'utc')::date`)を基準にしている。ここをローカル日付の0時で判定すると、
/// UTCとの時差分だけ「クライアント上は未達成に見えるがRPCは達成済みとして例外を返す」
/// 期間が生まれてしまう（例: JSTは UTC+9 のため、ローカル日付が変わってから9時間はUTC日付が
/// 変わっていない）ため、必ずUTC基準で揃える。
final hasCompletedDailyTodayProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return false;

  final nowUtc = DateTime.now().toUtc();
  final startOfDay = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);

  final rows = await supabase
      .from('quiz_responses')
      .select('id, quiz_questions!inner(kind)')
      .eq('user_id', userId)
      .eq('quiz_questions.kind', 'daily')
      .gte('answered_at', startOfDay.toIso8601String())
      .limit(1);
  return rows.isNotEmpty;
});

const _kDailyQuizPromptShownDatePrefsKey = 'daily_quiz_prompt_last_shown_date';

/// design/product.md 3.15節「アプリ起動時のデイリークイズ確認ダイアログ」。
/// UTC日付基準で「本日すでにダイアログを表示したか」をSharedPreferencesに永続化し、
/// 1日1回だけ表示されるようにする（アプリ再起動しても再表示されないように端末ローカルへ保存する）。
Future<bool> shouldShowDailyQuizPrompt() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kDailyQuizPromptShownDatePrefsKey) != _todayUtcDateString();
}

Future<void> markDailyQuizPromptShown() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kDailyQuizPromptShownDatePrefsKey, _todayUtcDateString());
}

String _todayUtcDateString() {
  final utc = DateTime.now().toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
}

/// award_daily_completion_tp RPCの戻り値。連続日数・今回付与TP・更新後残高をUIへ伝える。
class DailyCompletionResult {
  const DailyCompletionResult({
    required this.streakCount,
    required this.awardedTp,
    required this.newBalance,
  });

  final int streakCount;
  final double awardedTp;
  final double newBalance;
}

class QuizController {
  QuizController(this.ref);

  final Ref ref;

  Future<void> submitAnswer({
    required String userId,
    required String questionId,
    required bool isCorrect,
    required int responseTimeMs,
  }) async {
    await supabase.from('quiz_responses').insert({
      'user_id': userId,
      'question_id': questionId,
      'is_correct': isCorrect,
      'response_time_ms': responseTimeMs,
    });
  }

  /// design/product.md 3.2節「デイリーミッション: クリアでTPとボーナスポイントを付与。
  /// 連続日数ボーナスあり」。
  /// 3問クリアで基礎30 TPに加え、連続達成日数に応じたボーナスTPを付与する
  /// （award_daily_completion_tp RPC側で3日ごと/7日ごとのボーナスと連続日数更新をアトミックに行う）。
  /// 戻り値は更新後の連続日数・今回の付与TP・TP残高で、UI側のフィードバック表示に使える。
  Future<DailyCompletionResult> awardDailyCompletionTp() async {
    final response = await supabase.rpc('award_daily_completion_tp', params: {'p_base_amount': 30});
    final row = (response as List).first as Map<String, dynamic>;
    return DailyCompletionResult(
      streakCount: (row['new_streak_count'] as num).toInt(),
      awardedTp: (row['awarded_tp'] as num).toDouble(),
      newBalance: (row['new_balance'] as num).toDouble(),
    );
  }

  /// [kind]の完了状態のみを無効化する。
  ///
  /// 以前は無条件で両方を無効化していたが、`hasCompletedOnboardingProvider`は
  /// `_AuthRefreshListenable`（`lib/app/router.dart`）が購読しておりgo_routerの`redirect`を
  /// 再評価させる。`/daily-quiz`は`_onboardingExemptPaths`の対象外のため、デイリークイズ完了時に
  /// 無関係な`hasCompletedOnboardingProvider`まで無効化すると、その再評価の巻き添えで
  /// `/daily-quiz`画面が結果表示（`_finished = true`へのsetState）の直前に破棄されてしまい、
  /// TP付与自体は成功するのに結果サマリー画面が一切表示されないままフィードへ戻る不具合になっていた。
  void invalidateCompletionStatus(QuizKind kind) {
    switch (kind) {
      case QuizKind.onboarding:
        ref.invalidate(hasCompletedOnboardingProvider);
      case QuizKind.daily:
        ref.invalidate(hasCompletedDailyTodayProvider);
      case QuizKind.lockQuiz:
        break;
    }
  }
}

final quizControllerProvider = Provider<QuizController>((ref) {
  return QuizController(ref);
});
