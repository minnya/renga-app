/// design/system.md 15章「ダイレクトメッセージ（DM）」。DM一覧表示用のサマリーモデル。
///
/// `dm_conversations`と相手の`profiles`・最新メッセージ・未読数を組み合わせて
/// [MessagesController]（`messages_controller.dart`）側で組み立てる。
class DmConversationSummary {
  const DmConversationSummary({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    required this.otherAvatarUrl,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.unreadCount,
  });

  final String id;
  final String otherUserId;
  final String? otherUsername;
  final String? otherAvatarUrl;
  final DateTime lastMessageAt;
  final String lastMessagePreview;
  final int unreadCount;
}
