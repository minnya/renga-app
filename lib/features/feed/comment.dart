/// design/system.md 1章の `comments` テーブルに対応するコメントモデル。
/// design/product.md 3.12節「基本エンゲージメント機能」。
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorUsername,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String authorId;
  final String? authorUsername;
  final String body;
  final DateTime createdAt;

  factory Comment.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? username;
    if (profile is Map) {
      username = profile['username'] as String?;
    }

    return Comment(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      authorId: map['author_id'] as String,
      authorUsername: username,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
