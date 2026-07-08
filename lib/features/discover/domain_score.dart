/// design/system.md 1章の `domain_scores` テーブルに対応するモデル。
///
/// design/product.md 3.5節「AI自動専門家発掘システム」のドメイン別スコア・バッジを表す。
class DomainScore {
  const DomainScore({
    required this.userId,
    required this.domain,
    required this.score,
    required this.badgeTier,
    required this.updatedAt,
    required this.username,
    required this.avatarUrl,
  });

  final String userId;
  final String domain;
  final num score;

  /// null | expert | master
  final String? badgeTier;
  final DateTime updatedAt;

  final String? username;
  final String? avatarUrl;

  /// Supabaseの `domain_scores` テーブルへのネストselect（`profiles(username, avatar_url)`）
  /// 結果からパースする。
  factory DomainScore.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? username;
    String? avatarUrl;
    if (profile is Map) {
      username = profile['username'] as String?;
      avatarUrl = profile['avatar_url'] as String?;
    }

    return DomainScore(
      userId: map['user_id'] as String,
      domain: map['domain'] as String,
      score: map['score'] as num,
      badgeTier: map['badge_tier'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
      username: username,
      avatarUrl: avatarUrl,
    );
  }
}
