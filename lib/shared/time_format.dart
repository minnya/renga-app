import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';

/// 一覧画面用の相対時間表示（「3分前」「2日前」など）。
/// 7日以上経過した場合は日付表示にフォールバックする。
String relativeTimeLabel(AppLocalizations l10n, DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return l10n.feedCommentTimeJustNow;
  if (diff.inHours < 1) return l10n.feedCommentTimeMinutesAgo(diff.inMinutes);
  if (diff.inDays < 1) return l10n.feedCommentTimeHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.feedCommentTimeDaysAgo(diff.inDays);
  return DateFormat.yMd().format(dateTime.toLocal());
}

/// 詳細画面用の絶対時刻表示（`MM/dd HH:mm`）。
String absoluteTimeLabel(DateTime dateTime) {
  final local = dateTime.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}
