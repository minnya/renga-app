/// design/system.md 1章の `battles` テーブルに対応するモデル。
///
/// 対象投稿（target_post）・挑戦投稿（challenger_post）の本文をネストselectで
/// 併せて取得し、一覧・詳細表示に必要な最小限のフィールドを保持する。
class Battle {
  const Battle({
    required this.id,
    required this.targetPostId,
    required this.targetPostBody,
    required this.targetPostAuthorUsername,
    required this.challengerId,
    required this.challengerPostId,
    required this.challengerPostBody,
    required this.challengerPostAuthorUsername,
    required this.status,
    required this.challengerStakeTp,
    required this.defenderStakeTp,
    required this.winner,
    required this.resolvesAt,
    required this.createdAt,
  });

  final String id;
  final String targetPostId;
  final String? targetPostBody;
  final String? targetPostAuthorUsername;
  final String challengerId;
  final String? challengerPostId;
  final String? challengerPostBody;
  final String? challengerPostAuthorUsername;

  /// active | resolved
  final String status;
  final num challengerStakeTp;
  final num defenderStakeTp;

  /// challenger | defender | null（未確定）
  final String? winner;
  final DateTime resolvesAt;
  final DateTime createdAt;

  /// 挑戦者・防衛者の合計ステークTP（一覧カードの「賭けTP合計」表示用）。
  num get totalStakeTp => challengerStakeTp + defenderStakeTp;

  bool get isActive => status == 'active';

  /// 決着までの残り時間。過ぎている場合はゼロを返す。
  Duration get remaining {
    final diff = resolvesAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Supabaseの `battles` テーブルへのネストselect
  /// （`target_post:posts!battles_target_post_id_fkey(body, profiles(username))`,
  /// `challenger_post:posts!battles_challenger_post_id_fkey(body, profiles(username))`）
  /// 結果からパースする。
  factory Battle.fromMap(Map<String, dynamic> map) {
    final targetPost = map['target_post'];
    String? targetBody;
    String? targetUsername;
    if (targetPost is Map) {
      targetBody = targetPost['body'] as String?;
      final profile = targetPost['profiles'];
      if (profile is Map) targetUsername = profile['username'] as String?;
    }

    final challengerPost = map['challenger_post'];
    String? challengerBody;
    String? challengerUsername;
    if (challengerPost is Map) {
      challengerBody = challengerPost['body'] as String?;
      final profile = challengerPost['profiles'];
      if (profile is Map) challengerUsername = profile['username'] as String?;
    }

    return Battle(
      id: map['id'] as String,
      targetPostId: map['target_post_id'] as String,
      targetPostBody: targetBody,
      targetPostAuthorUsername: targetUsername,
      challengerId: map['challenger_id'] as String,
      challengerPostId: map['challenger_post_id'] as String?,
      challengerPostBody: challengerBody,
      challengerPostAuthorUsername: challengerUsername,
      status: map['status'] as String? ?? 'active',
      challengerStakeTp: map['challenger_stake_tp'] as num? ?? 0,
      defenderStakeTp: map['defender_stake_tp'] as num? ?? 0,
      winner: map['winner'] as String?,
      resolvesAt: DateTime.parse(map['resolves_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// design/system.md 1章の `battle_bets` テーブルに対応する観客ベットモデル。
class BattleBet {
  const BattleBet({
    required this.id,
    required this.battleId,
    required this.userId,
    required this.side,
    required this.amountTp,
    required this.payoutTp,
    required this.createdAt,
  });

  final String id;
  final String battleId;
  final String userId;

  /// challenger | defender
  final String side;
  final num amountTp;
  final num? payoutTp;
  final DateTime createdAt;

  factory BattleBet.fromMap(Map<String, dynamic> map) {
    return BattleBet(
      id: map['id'] as String,
      battleId: map['battle_id'] as String,
      userId: map['user_id'] as String,
      side: map['side'] as String,
      amountTp: map['amount_tp'] as num,
      payoutTp: map['payout_tp'] as num?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
