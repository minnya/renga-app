import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import 'notification.dart';
import 'notifications_controller.dart';

/// design/product.md 4章「Notification（Endorse獲得、バッジ実績解除、ストライク通知）」画面。
/// Instagram風アクティビティ一覧として、通知種別アイコン + 本文 + 日時のシンプルな横並びリスト行で実装。
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsAppBarTitle)),
      body: currentUser == null
          ? Center(child: Text(l10n.notificationsSignedOutMessage))
          : _NotificationsList(userId: currentUser.id),
    );
  }
}

class _NotificationsList extends ConsumerWidget {
  const _NotificationsList({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notificationsAsync = ref.watch(notificationsProvider(userId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(notificationsProvider(userId));
        await ref.read(notificationsProvider(userId).future);
      },
      child: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text(l10n.notificationsEmpty)),
                ),
              ],
            );
          }
          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outline,
              thickness: 0.5,
            ),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return _NotificationTile(
                notification: notification,
                onTap: () {
                  if (!notification.isRead) {
                    ref
                        .read(notificationsControllerProvider)
                        .markAsRead(userId: userId, notificationId: notification.id);
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(l10n.notificationsLoadError('$error'))),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final NotificationItem notification;
  final VoidCallback onTap;

  /// 通知種別（kind）に応じてアイコンを選択。
  IconData _getIconForKind(String kind) {
    switch (kind) {
      case 'endorse_received':
        return Icons.star;
      case 'badge_unlocked':
        return Icons.emoji_events;
      case 'strike_warning':
        return Icons.warning_rounded;
      default:
        return Icons.notifications;
    }
  }

  /// DateTime を相対時間文字列に変換（例："2時間前", "1日前"）。
  /// 現在、locale 対応はしていない（設定言語に応じて後で拡張可能）。
  String _formatRelativeTime(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inSeconds < 60) {
      return 'now';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '${minutes}m ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '${hours}h ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '${days}d ago';
    } else {
      return 'long ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isUnread
          ? (isDark
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.primary.withValues(alpha: 0.05))
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // アイコン（通知種別対応）
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 4),
                child: Icon(
                  _getIconForKind(notification.kind),
                  size: 24,
                  color: isUnread
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // 本文と日時を縦積みしたテキスト領域
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // タイトル（未読ならボールド）
                    Text(
                      notification.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 本文（存在すれば表示）
                    if (notification.body != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        notification.body!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // 日時（相対時間）
                    const SizedBox(height: 6),
                    Text(
                      _formatRelativeTime(notification.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
