/// design/system.md 1章の `comments` テーブルに対応するコメントモデル。
/// design/product.md 3.12節「基本エンゲージメント機能」。
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorUsername,
    required this.authorAvatarUrl,
    required this.body,
    required this.createdAt,
    this.parentCommentId,
    this.mediaUrls,
    this.externalVideoUrl,
  });

  final String id;
  final String postId;
  final String authorId;
  final String? authorUsername;
  final String? authorAvatarUrl;
  final String body;
  final DateTime createdAt;

  /// 返信スレッド用（1階層）。nullはトップレベルコメント。
  final String? parentCommentId;

  /// コメント・返信への画像添付URL（複数可）。
  final List<String>? mediaUrls;

  /// コメント・返信への動画添付（Mux連携。`videos`テーブルの`comment_id`で紐づく）のURLではなく、
  /// 外部動画URL（YouTube等）用。Mux動画自体は別途`videos`テーブルを参照する。
  final String? externalVideoUrl;

  bool get isReply => parentCommentId != null;

  factory Comment.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? username;
    String? avatarUrl;
    if (profile is Map) {
      username = profile['username'] as String?;
      avatarUrl = profile['avatar_url'] as String?;
    }

    final rawMediaUrls = map['media_urls'];

    return Comment(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      authorId: map['author_id'] as String,
      authorUsername: username,
      authorAvatarUrl: avatarUrl,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      parentCommentId: map['parent_comment_id'] as String?,
      mediaUrls: rawMediaUrls is List ? rawMediaUrls.map((e) => e as String).toList() : null,
      externalVideoUrl: map['external_video_url'] as String?,
    );
  }
}
