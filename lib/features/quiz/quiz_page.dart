import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_state.dart';
import 'quiz_controller.dart';
import 'quiz_question.dart';

/// design/product.md 3章のオンボーディングクイズ/デイリーミッションの共通画面。
class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({super.key, required this.kind});

  final QuizKind kind;

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  List<QuizQuestion>? _questions;
  int _currentIndex = 0;
  int _correctCount = 0;
  int _remainingSeconds = 0;
  Timer? _timer;
  Stopwatch? _stopwatch;
  bool _answeredCurrent = false;
  bool _finished = false;
  bool _tpAwarded = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initializeIfNeeded(List<QuizQuestion> questions) {
    if (_questions != null) return;
    _questions = questions;
    if (questions.isNotEmpty) {
      _startQuestionTimer(questions.first);
    } else {
      _finished = true;
    }
  }

  void _startQuestionTimer(QuizQuestion question) {
    _timer?.cancel();
    _stopwatch = Stopwatch()..start();
    _answeredCurrent = false;
    setState(() => _remainingSeconds = question.timeLimitSeconds);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remainingSeconds--);
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _handleAnswer(null);
      }
    });
  }

  Future<void> _handleAnswer(String? selectedChoice) async {
    if (_answeredCurrent) return;
    _answeredCurrent = true;
    _timer?.cancel();

    final question = _questions![_currentIndex];
    final isCorrect = selectedChoice == question.correctAnswer;
    final responseTimeMs = _stopwatch?.elapsedMilliseconds ?? 0;
    final userId = ref.read(currentUserProvider)?.id;

    if (userId != null) {
      await ref.read(quizControllerProvider).submitAnswer(
            userId: userId,
            questionId: question.id,
            isCorrect: isCorrect,
            responseTimeMs: responseTimeMs,
          );
    }

    if (!mounted) return;
    setState(() {
      if (isCorrect) _correctCount++;
    });

    if (_currentIndex + 1 < _questions!.length) {
      setState(() => _currentIndex++);
      _startQuestionTimer(_questions![_currentIndex]);
    } else {
      await _handleFinish();
    }
  }

  Future<void> _handleFinish() async {
    if (widget.kind == QuizKind.daily && !_tpAwarded) {
      await ref.read(quizControllerProvider).awardDailyCompletionTp();
      _tpAwarded = true;
    }
    ref.read(quizControllerProvider).invalidateCompletionStatus();
    if (!mounted) return;
    setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = widget.kind == QuizKind.onboarding
        ? ref.watch(onboardingQuestionsProvider)
        : ref.watch(dailyQuestionsProvider);

    final title = widget.kind == QuizKind.onboarding ? 'オンボーディングクイズ' : 'デイリークイズ';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: questionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('問題の取得に失敗しました: $error')),
        data: (questions) {
          _initializeIfNeeded(questions);

          if (_questions!.isEmpty) {
            return const Center(child: Text('現在出題可能な問題がありません'));
          }
          if (_finished) {
            return _QuizResultView(
              correctCount: _correctCount,
              total: _questions!.length,
              tpAwarded: widget.kind == QuizKind.daily,
            );
          }

          final question = _questions![_currentIndex];
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '問題 ${_currentIndex + 1} / ${_questions!.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text('残り $_remainingSeconds 秒', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                Text(question.questionText, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),
                ...question.choices.map(
                  (choice) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton(
                      onPressed: () => _handleAnswer(choice),
                      child: Align(alignment: Alignment.centerLeft, child: Text(choice)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QuizResultView extends StatelessWidget {
  const _QuizResultView({required this.correctCount, required this.total, required this.tpAwarded});

  final int correctCount;
  final int total;
  final bool tpAwarded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('結果: $correctCount / $total 問正解', style: Theme.of(context).textTheme.headlineSmall),
            if (tpAwarded) ...[
              const SizedBox(height: 12),
              const Text('TPを30獲得しました！'),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('フィードへ戻る'),
            ),
          ],
        ),
      ),
    );
  }
}
