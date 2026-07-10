/// design/product.md 3.4節「TP消費投稿とロジックチェック（Discover内・真偽投票）」。
/// `supabase/migrations/20260709150000_truth_judgment_system.sql` の
/// `truth_judgment_requests` テーブルに対応するモデル。
class TruthJudgmentRequest {
  const TruthJudgmentRequest({
    required this.id,
    required this.postId,
    required this.requestedBy,
    required this.authorIntellectPercentileSnapshot,
    required this.status,
    required this.trueVoteCount,
    required this.falseVoteCount,
    required this.quorumThreshold,
    required this.opensAt,
    required this.closesAt,
    required this.createdAt,
    this.resolvedVerdict,
    this.resolvedAt,
  });

  final String id;
  final String postId;
  final String requestedBy;

  /// リクエスト起票時点の投稿者の`intellect_percentile`スナップショット。投票資格判定
  /// （投票者の`intellect_percentile`がこの値以下であること）に使う。
  final num authorIntellectPercentileSnapshot;

  /// voting | resolved | invalid
  final String status;
  final bool? resolvedVerdict;
  final int trueVoteCount;
  final int falseVoteCount;
  final int quorumThreshold;
  final DateTime opensAt;
  final DateTime closesAt;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  bool get isVoting => status == 'voting';
  bool get isResolved => status == 'resolved';
  bool get isInvalid => status == 'invalid';

  factory TruthJudgmentRequest.fromMap(Map<String, dynamic> map) {
    return TruthJudgmentRequest(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      requestedBy: map['requested_by'] as String,
      authorIntellectPercentileSnapshot:
          map['author_intellect_percentile_snapshot'] as num,
      status: map['status'] as String? ?? 'voting',
      resolvedVerdict: map['resolved_verdict'] as bool?,
      trueVoteCount: map['true_vote_count'] as int? ?? 0,
      falseVoteCount: map['false_vote_count'] as int? ?? 0,
      quorumThreshold: map['quorum_threshold'] as int? ?? 10,
      opensAt: DateTime.parse(map['opens_at'] as String),
      closesAt: DateTime.parse(map['closes_at'] as String),
      resolvedAt: map['resolved_at'] == null
          ? null
          : DateTime.parse(map['resolved_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// `truth_votes` テーブルに対応するモデル。ユーザー1人につき1リクエストあたり1票のみ
/// （`unique(request_id, user_id)`）。
class TruthVote {
  const TruthVote({
    required this.id,
    required this.requestId,
    required this.userId,
    required this.verdict,
    required this.voterTier,
    required this.createdAt,
    this.payoutTp,
  });

  final String id;
  final String requestId;
  final String userId;

  /// true=本当, false=嘘
  final bool verdict;

  /// 投票時点の知能階層。'top5' | 'top25'（product.md 3.4.4節の2階建てメーター集計に使用）。
  final String voterTier;
  final num? payoutTp;
  final DateTime createdAt;

  bool get isTop5 => voterTier == 'top5';

  factory TruthVote.fromMap(Map<String, dynamic> map) {
    return TruthVote(
      id: map['id'] as String,
      requestId: map['request_id'] as String,
      userId: map['user_id'] as String,
      verdict: map['verdict'] as bool,
      voterTier: map['voter_tier'] as String? ?? 'top25',
      payoutTp: map['payout_tp'] as num?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
