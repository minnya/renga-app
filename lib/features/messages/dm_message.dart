/// design/system.md 15章「ダイレクトメッセージ（DM）」。`dm_messages`テーブル1行分のモデル。
///
/// `media_type`は`text`/`image`/`video`のいずれか。テキストのみの場合は
/// [mediaUrl]・[muxPlaybackId]ともにnull。
class DmMessage {
  const DmMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.mediaType,
    required this.mediaUrl,
    required this.muxPlaybackId,
    required this.readAt,
    required this.createdAt,
  });

  factory DmMessage.fromMap(Map<String, dynamic> map) {
    return DmMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      body: map['body'] as String?,
      mediaType: map['media_type'] as String? ?? 'text',
      mediaUrl: map['media_url'] as String?,
      muxPlaybackId: map['mux_playback_id'] as String?,
      readAt: map['read_at'] != null ? DateTime.parse(map['read_at'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final String? body;
  final String mediaType;
  final String? mediaUrl;
  final String? muxPlaybackId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isText => mediaType == 'text';
  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
}
