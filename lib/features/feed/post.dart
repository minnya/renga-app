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
    required this.mediaType,
    required this.mediaUrls,
    required this.authorIntellectPercentile,
  });

  final String id;
  final String authorId;
  final String? authorUsername;
  final String body;
  final DateTime createdAt;
  final String mediaType;
  final List<String>? mediaUrls;

  /// design/product.md 4章「上位25%/5%知能バッジ」判定用。値が小さいほど上位を表す
  /// （例: 上位5% → `intellect_percentile <= 5`）。スコアリングパイプライン未実装のため
  /// 現状は全ユーザーで`0`のまま。
  final num? authorIntellectPercentile;

  /// Supabaseの `posts` テーブルへのネストselect（`profiles(username, intellect_percentile)`）
  /// 結果からパースする。
  factory Post.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? username;
    num? intellectPercentile;
    if (profile is Map) {
      username = profile['username'] as String?;
      intellectPercentile = profile['intellect_percentile'] as num?;
    }

    final rawMediaUrls = map['media_urls'];
    final mediaUrls = rawMediaUrls is List
        ? rawMediaUrls.map((e) => e as String).toList()
        : null;

    return Post(
      id: map['id'] as String,
      authorId: map['author_id'] as String,
      authorUsername: username,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      mediaType: map['media_type'] as String? ?? 'text',
      mediaUrls: mediaUrls,
      authorIntellectPercentile: intellectPercentile,
    );
  }
}
