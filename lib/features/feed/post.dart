/// design/system.md 1章の `posts` テーブルに対応する投稿モデル。
///
/// フィード表示に必要な最小限のフィールドのみを保持する。
class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorUsername,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String? authorUsername;
  final String body;
  final DateTime createdAt;

  /// Supabaseの `posts` テーブルへのネストselect（`profiles(username)`）結果からパースする。
  factory Post.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? username;
    if (profile is Map<String, dynamic>) {
      username = profile['username'] as String?;
    } else if (profile is Map) {
      username = profile['username'] as String?;
    }

    return Post(
      id: map['id'] as String,
      authorId: map['author_id'] as String,
      authorUsername: username,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
