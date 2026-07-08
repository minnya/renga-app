import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';
import 'quiz_question.dart';

/// design/product.md 3.2節「ロック解除クイズ（通行料）」に対応する`lockQuiz`を追加。
/// ステーキング投稿の直前に義務化される1〜2問のクイズ種別。
enum QuizKind { onboarding, daily, lockQuiz }

extension QuizKindX on QuizKind {
  String get value => switch (this) {
        QuizKind.onboarding => 'onboarding',
        QuizKind.daily => 'daily',
        QuizKind.lockQuiz => 'lock_quiz',
      };
}

/// design/product.md 3章「オンボーディングクイズ: 初回登録時に3問」。
/// プールは4問用意し、先頭3問を使用する。
final onboardingQuestionsProvider = FutureProvider<List<QuizQuestion>>((ref) async {
  final rows = await supabase
      .from('quiz_questions')
      .select()
      .eq('kind', 'onboarding')
      .eq('is_active', true)
      .order('created_at')
      .limit(3);
  return rows.map((row) => QuizQuestion.fromMap(row)).toList();
});

/// design/product.md 3章「デイリーミッション: 1日3問」。
/// プール(6問)からランダムに3問抽出する。
final dailyQuestionsProvider = FutureProvider<List<QuizQuestion>>((ref) async {
  final rows = await supabase
      .from('quiz_questions')
      .select()
      .eq('kind', 'daily')
      .eq('is_active', true);
  final questions = rows.map((row) => QuizQuestion.fromMap(row)).toList();
  questions.shuffle(Random());
  return questions.take(3).toList();
});

/// design/product.md 3.2節「ロック解除クイズ（通行料）: シリアス投稿(ステーキング)時に1〜2問を義務化」。
/// プール(4問)からランダムに2問抽出する。TP付与は行わず、通行料としての正誤判定のみに使う。
final lockQuizQuestionsProvider = FutureProvider.autoDispose<List<QuizQuestion>>((ref) async {
  final rows = await supabase
      .from('quiz_questions')
      .select()
      .eq('kind', 'lock_quiz')
      .eq('is_active', true);
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

/// 現在のユーザーが本日デイリークイズに回答済みかどうか（ローカル日付の0時基準）。
final hasCompletedDailyTodayProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return false;

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day).toUtc();

  final rows = await supabase
      .from('quiz_responses')
      .select('id, quiz_questions!inner(kind)')
      .eq('user_id', userId)
      .eq('quiz_questions.kind', 'daily')
      .gte('answered_at', startOfDay.toIso8601String())
      .limit(1);
  return rows.isNotEmpty;
});

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

  /// design/product.md 3章「デイリーミッション: クリアでTPを付与」。
  /// 3問クリアで固定30 TPを付与する（連続日数ボーナスは対象外）。
  Future<void> awardDailyCompletionTp() async {
    await supabase.rpc('increment_tp_balance', params: {'p_amount': 30});
  }

  void invalidateCompletionStatus() {
    ref.invalidate(hasCompletedOnboardingProvider);
    ref.invalidate(hasCompletedDailyTodayProvider);
  }
}

final quizControllerProvider = Provider<QuizController>((ref) {
  return QuizController(ref);
});
