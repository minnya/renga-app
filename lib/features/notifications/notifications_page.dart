import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import 'notification.dart';
import 'notifications_controller.dart';

/// design/product.md 4章「Notification（Endorse獲得、バッジ実績解除、ストライク通知）」画面。
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
            separatorBuilder: (context, index) => const Divider(height: 1),
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

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;

    return ListTile(
      leading: Icon(
        isUnread ? Icons.circle_notifications : Icons.notifications_none,
        color: isUnread ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        notification.title,
        style: TextStyle(fontWeight: isUnread ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: notification.body != null ? Text(notification.body!) : null,
      onTap: onTap,
    );
  }
}
