/// `notifications` テーブルに対応する通知モデル。
///
/// design/product.md 4章「Notification（Endorse獲得、バッジ実績解除、ストライク通知）」で
/// 挙げられる通知種別を `kind` に自由記述のtextとして保持する
/// （endorse_received / badge_unlocked / battle_resolved / strike_warning 等）。
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.body,
    required this.relatedPostId,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String kind;
  final String title;
  final String? body;
  final String? relatedPostId;
  final bool isRead;
  final DateTime createdAt;

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    return NotificationItem(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      kind: map['kind'] as String,
      title: map['title'] as String,
      body: map['body'] as String?,
      relatedPostId: map['related_post_id'] as String?,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
