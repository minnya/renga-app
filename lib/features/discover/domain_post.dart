/// design/system.md 1章の `posts` テーブルのうち、Discover画面の
/// 「このドメインの投稿」セクション表示に必要な最小限のフィールドを持つモデル。
class DomainPost {
  const DomainPost({
    required this.id,
    required this.body,
    required this.mediaType,
    required this.mediaUrls,
    required this.createdAt,
    required this.authorId,
    required this.username,
    required this.avatarUrl,
  });

  final String id;
  final String body;
  final String? mediaType;
  final List<String> mediaUrls;
  final DateTime createdAt;
  final String authorId;

  final String? username;
  final String? avatarUrl;

  /// Supabaseの `posts` テーブルへのネストselect（`profiles(username, avatar_url)`）
  /// 結果からパースする。
  factory DomainPost.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? username;
    String? avatarUrl;
    if (profile is Map) {
      username = profile['username'] as String?;
      avatarUrl = profile['avatar_url'] as String?;
    }

    final rawMediaUrls = map['media_urls'];
    final mediaUrls = rawMediaUrls is List
        ? rawMediaUrls.map((e) => e.toString()).toList()
        : <String>[];

    return DomainPost(
      id: map['id'] as String,
      body: map['body'] as String? ?? '',
      mediaType: map['media_type'] as String?,
      mediaUrls: mediaUrls,
      createdAt: DateTime.parse(map['created_at'] as String),
      authorId: map['author_id'] as String,
      username: username,
      avatarUrl: avatarUrl,
    );
  }
}
