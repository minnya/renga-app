# fix: daily-quiz result view claims TP earned on award RPC failure

## bug
found via Playwright scenario test (fresh signup -> onboarding -> daily quiz e2e).
`lib/features/quiz/quiz_page.dart::_QuizResultView`
```
tpAwarded: widget.kind == QuizKind.daily,   // <- kind check only, ignores RPC outcome
dailyResult: _dailyResult,                 // null both while loading (impossible, always awaited) AND on RPC failure
```
render branch:
```
if (tpAwarded && result != null) -> real TP+streak (award succeeded)
else if (tpAwarded)              -> l10n.quizTpAwardedGeneric = "You earned TP!"  // ALWAYS the failure path in practice
```
`_dailyResult` is set by `awardDailyCompletionTp()` in `_handleFinish`; on throw (e.g. `award_daily_completion_tp` RPC's
multi-award-guard exception when retaking after already completing today, confirmed via direct nav to `/daily-quiz`
post-completion) the catch block only shows a transient SnackBar and leaves `_dailyResult == null`.
=> result screen still says "You earned TP!" even though TP was NOT awarded (verified: `profiles.tp_balance`
unchanged across the failed retake in prod DB).

## fix
- add `bool _dailyAwardFailed` state in `_QuizPageState`, set `true` in the `catch` of `_handleFinish`.
- pass to `_QuizResultView` instead of the `result != null ? real : generic` binary.
- new l10n key `quizTpAwardFailed` (en/ja) for the failure branch; do not reuse `quizTpAwardedGeneric`
  (misleading string, kept as-is / unused elsewhere, not in scope to delete).
- render:
  ```
  if daily && result != null        -> real TP + streak
  else if daily && _dailyAwardFailed -> l10n.quizTpAwardFailed (honest, no TP claim)
  ```
  (the old unconditional-generic-success branch is removed; there is no other daily+null+non-failure case in
  practice since the RPC call is always awaited synchronously before `_finished` is set.)

## files touched
- lib/l10n/app_en.arb, app_ja.arb (+ regenerate gen/)
- lib/features/quiz/quiz_page.dart
