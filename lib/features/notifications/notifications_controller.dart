import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import 'notification.dart';

/// design/product.md 4章「Notification」画面用に、自分宛の通知一覧
/// （作成日時降順・最大50件）を取得する。RLSにより本人の通知のみ取得できる。
final notificationsProvider = FutureProvider.family<List<NotificationItem>, String>((
  ref,
  userId,
) async {
  final rows = await supabase
      .from('notifications')
      .select()
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(50);

  return rows.map((row) => NotificationItem.fromMap(row)).toList();
});

/// 通知の既読化処理をまとめたコントローラー。
class NotificationsController {
  NotificationsController(this.ref);

  final Ref ref;

  /// 指定した通知を既読化し、該当ユーザーの [notificationsProvider] を再取得させる。
  Future<void> markAsRead({required String userId, required String notificationId}) async {
    await supabase.from('notifications').update({'is_read': true}).eq('id', notificationId);

    ref.invalidate(notificationsProvider(userId));
  }
}

final notificationsControllerProvider = Provider<NotificationsController>((ref) {
  return NotificationsController(ref);
});
