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
/// design/product.md 3.14節に従い、正誤フィードバックと「次へ」ボタンは別ページへ遷移せず、
/// 設問画面の上に重ねるオーバーレイパネルとして表示する。
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

  // design/product.md 3.14節「回答結果フィードバック」。
  bool _showingFeedback = false;
  String? _selectedChoice;
  bool _lastAnswerCorrect = false;

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
      _selectedChoice = selectedChoice;
      _lastAnswerCorrect = isCorrect;
      _showingFeedback = true;
    });
  }

  /// フィードバックオーバーレイの「次へ」ボタン押下時。
  /// [QuizPage]と同様、フィードバック非表示と次状態への遷移を同一のsetStateで行い、
  /// 集計中に設問画面へ一瞬戻って見えることによる「結果が表示されない」体験を避ける。
  void _handleNext() {
    if (_currentIndex + 1 < _questions!.length) {
      setState(() {
        _showingFeedback = false;
        _currentIndex++;
      });
      _startQuestionTimer(_questions![_currentIndex]);
    } else {
      setState(() {
        _showingFeedback = false;
        _finished = true;
      });
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
            final isLastQuestion = _currentIndex + 1 >= _questions!.length;

            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.lockQuizProgress(_currentIndex + 1, _questions!.length),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.quizRemainingSeconds(_remainingSeconds),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      Text(question.questionText, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 24),
                      ...question.choices.map(
                        (choice) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OutlinedButton(
                            onPressed: _showingFeedback ? null : () => _handleAnswer(choice),
                            child: Align(alignment: Alignment.centerLeft, child: Text(choice)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _QuizFeedbackOverlay(
                  visible: _showingFeedback,
                  isCorrect: _lastAnswerCorrect,
                  selectedChoice: _selectedChoice,
                  correctAnswer: question.correctAnswer,
                  isLastQuestion: isLastQuestion,
                  onNext: _handleNext,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// design/product.md 3.14節「回答結果フィードバック」に対応する正誤フィードバック＋
/// 「次へ」ボタンのオーバーレイ。[QuizPage]のものと同じ見た目・アニメーション方針
/// （ボトムシート相当の角丸パネル＋背後の半透明スクリム、下からのスライド＋フェード）に揃える。
class _QuizFeedbackOverlay extends StatelessWidget {
  const _QuizFeedbackOverlay({
    required this.visible,
    required this.isCorrect,
    required this.selectedChoice,
    required this.correctAnswer,
    required this.isLastQuestion,
    required this.onNext,
  });

  final bool visible;
  final bool isCorrect;
  final String? selectedChoice;
  final String correctAnswer;
  final bool isLastQuestion;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      ignoring: !visible,
      child: Stack(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: visible ? 1 : 0,
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              offset: visible ? Offset.zero : const Offset(0, 1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: visible ? 1 : 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isCorrect ? Icons.check_circle : Icons.cancel,
                              color: isCorrect ? Colors.green : Colors.red,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isCorrect ? l10n.quizFeedbackCorrect : l10n.quizFeedbackIncorrect,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      color: isCorrect ? Colors.green : Colors.red,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        if (!isCorrect) ...[
                          const SizedBox(height: 12),
                          if (selectedChoice != null)
                            Text(
                              selectedChoice!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    decoration: TextDecoration.lineThrough,
                                  ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.quizFeedbackCorrectAnswer(correctAnswer),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: onNext,
                          child: Text(isLastQuestion ? l10n.quizSeeResultButton : l10n.quizNextButton),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
