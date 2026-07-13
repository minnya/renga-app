import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
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
  DailyCompletionResult? _dailyResult;

  // design/product.md 3.14節「回答結果フィードバック」。
  // 選択直後は設問画面の上にオーバーレイパネルで正誤フィードバックを表示し、
  // 明示的な「次へ」操作で次の設問に進む（別ページには遷移しない）。
  bool _showingFeedback = false;
  String? _selectedChoice;
  bool _lastAnswerCorrect = false;
  // 最後の設問で「結果を見る」を押してから結果サマリー表示に切り替わるまでの間、
  // オーバーレイを表示し続けつつボタンをローディング状態にするためのフラグ。
  bool _finishing = false;

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

  /// フィードバックオーバーレイの「次へ」/「結果を見る」ボタン押下時。
  ///
  /// 最後の設問の場合は`_handleFinish`の完了（デイリーミッションのTP付与RPC等）を
  /// 待つ間もオーバーレイを表示し続ける。ここで先に`_showingFeedback`を倒してしまうと、
  /// 集計処理待ちの間だけ設問画面へ一瞬戻ったように見え、「結果を見るを押しても
  /// 何も起きない」ように見える不具合になるため、次の設問へ進む場合と結果サマリーへ
  /// 進む場合のいずれも、フィードバック非表示と次状態への遷移を同一のsetStateで行う。
  Future<void> _handleNext() async {
    if (_currentIndex + 1 < _questions!.length) {
      setState(() {
        _showingFeedback = false;
        _currentIndex++;
      });
      _startQuestionTimer(_questions![_currentIndex]);
    } else {
      setState(() => _finishing = true);
      await _handleFinish();
    }
  }

  /// TP付与RPC（`award_daily_completion_tp`）が失敗した場合（多重達成防止の例外・通信
  /// エラー等）でも、結果サマリー画面自体は必ず表示する。ここで例外を無視して
  /// `_finished`まで到達させないと、`_finishing`が立ったまま画面が固まり、「結果を見る」を
  /// 押しても何も起きない（ホームに戻ったように見える）不具合になる。
  Future<void> _handleFinish() async {
    if (widget.kind == QuizKind.daily && !_tpAwarded) {
      try {
        _dailyResult = await ref.read(quizControllerProvider).awardDailyCompletionTp();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
        }
      }
      _tpAwarded = true;
    }
    ref.read(quizControllerProvider).invalidateCompletionStatus();
    if (!mounted) return;
    setState(() {
      _showingFeedback = false;
      _finishing = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final questionsAsync = widget.kind == QuizKind.onboarding
        ? ref.watch(onboardingQuestionsProvider)
        : ref.watch(dailyQuestionsProvider);

    final title = widget.kind == QuizKind.onboarding ? l10n.quizOnboardingTitle : l10n.quizDailyTitle;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: questionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(l10n.quizLoadError('$error'))),
        data: (questions) {
          _initializeIfNeeded(questions);

          if (_questions!.isEmpty) {
            return Center(child: Text(l10n.quizNoQuestions));
          }
          if (_finished) {
            return _QuizResultView(
              correctCount: _correctCount,
              total: _questions!.length,
              tpAwarded: widget.kind == QuizKind.daily,
              dailyResult: _dailyResult,
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
                      l10n.quizProgress(_currentIndex + 1, _questions!.length),
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
                finishing: _finishing,
                onNext: _handleNext,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// design/product.md 3.14節「回答結果フィードバック」に対応する正誤フィードバック＋
/// 「次へ」ボタンのオーバーレイ。設問画面を別ページへ遷移させず、背後の設問の上に
/// ボトムシート相当の角丸パネルを重ね、5章の方針（フェード＋わずかなスライド）に沿って
/// 下から立ち上がる形で出現・消失させる。
class _QuizFeedbackOverlay extends StatelessWidget {
  const _QuizFeedbackOverlay({
    required this.visible,
    required this.isCorrect,
    required this.selectedChoice,
    required this.correctAnswer,
    required this.isLastQuestion,
    required this.finishing,
    required this.onNext,
  });

  final bool visible;
  final bool isCorrect;
  final String? selectedChoice;
  final String correctAnswer;
  final bool isLastQuestion;
  final bool finishing;
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
                          onPressed: finishing ? null : onNext,
                          child: finishing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(isLastQuestion ? l10n.quizSeeResultButton : l10n.quizNextButton),
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

class _QuizResultView extends StatelessWidget {
  const _QuizResultView({
    required this.correctCount,
    required this.total,
    required this.tpAwarded,
    this.dailyResult,
  });

  final int correctCount;
  final int total;
  final bool tpAwarded;
  final DailyCompletionResult? dailyResult;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = dailyResult;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.quizResult(correctCount, total), style: Theme.of(context).textTheme.headlineSmall),
            if (tpAwarded && result != null) ...[
              const SizedBox(height: 12),
              Text(l10n.quizTpAwardedAmount(result.awardedTp.toStringAsFixed(0))),
              const SizedBox(height: 4),
              Text(l10n.quizStreakCount(result.streakCount)),
            ] else if (tpAwarded) ...[
              const SizedBox(height: 12),
              Text(l10n.quizTpAwardedGeneric),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: Text(l10n.quizBackToFeed),
            ),
          ],
        ),
      ),
    );
  }
}
