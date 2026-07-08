import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import 'quiz_controller.dart';
import 'quiz_question.dart';

/// design/product.md 3.2節「ロック解除クイズ（通行料）」＋3.4節「ステーキング・ツイート」。
///
/// ステーキング投稿の直前に1〜2問を義務化し、冷却期間として荒らし・ボット投稿を抑制する。
/// [QuizPage]（オンボーディング/デイリー）のUIパターンを踏襲しつつ、
/// - TP付与は行わない（通行料としての正誤判定のみ）
/// - 全問正解した場合のみ投稿を許可する（1問でも不正解ならロック解除失敗）
/// という点が異なるため、専用のフルスクリーンダイアログとして実装する。
///
/// 呼び出し側は `await showLockQuizDialog(context)` で結果（true=全問正解/false=未達・キャンセル）を受け取る。
Future<bool> showLockQuizDialog(BuildContext context) async {
  final passed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LockQuizPage()),
  );
  return passed ?? false;
}

class LockQuizPage extends ConsumerStatefulWidget {
  const LockQuizPage({super.key});

  @override
  ConsumerState<LockQuizPage> createState() => _LockQuizPageState();
}

class _LockQuizPageState extends ConsumerState<LockQuizPage> {
  List<QuizQuestion>? _questions;
  int _currentIndex = 0;
  int _correctCount = 0;
  int _remainingSeconds = 0;
  Timer? _timer;
  Stopwatch? _stopwatch;
  bool _answeredCurrent = false;
  bool _finished = false;

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
      setState(() => _finished = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final questionsAsync = ref.watch(lockQuizQuestionsProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.lockQuizAppBarTitle),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.lockQuizCancelButton),
            ),
          ],
        ),
        body: questionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text(l10n.quizLoadError('$error'))),
          data: (questions) {
            _initializeIfNeeded(questions);

            if (_questions!.isEmpty) {
              return Center(child: Text(l10n.quizNoQuestions));
            }
            if (_finished) {
              final passed = _correctCount == _questions!.length;
              return _LockQuizResultView(
                passed: passed,
                correctCount: _correctCount,
                total: _questions!.length,
                onContinue: () => Navigator.of(context).pop(passed),
              );
            }

            final question = _questions![_currentIndex];
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.lockQuizProgress(_currentIndex + 1, _questions!.length),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.quizRemainingSeconds(_remainingSeconds), style: Theme.of(context).textTheme.bodyMedium),
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
      ),
    );
  }
}

class _LockQuizResultView extends StatelessWidget {
  const _LockQuizResultView({
    required this.passed,
    required this.correctCount,
    required this.total,
    required this.onContinue,
  });

  final bool passed;
  final int correctCount;
  final int total;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              passed ? Icons.lock_open : Icons.lock_outline,
              size: 48,
              color: passed ? Colors.green : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(l10n.quizResult(correctCount, total), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              passed ? l10n.lockQuizPassedMessage : l10n.lockQuizFailedMessage,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onContinue,
              child: Text(passed ? l10n.lockQuizContinueButton : l10n.lockQuizCloseButton),
            ),
          ],
        ),
      ),
    );
  }
}
