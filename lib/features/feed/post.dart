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
    required this.postType,
    required this.stakedTp,
    this.externalVideoUrl,
    this.externalVideoProvider,
    this.externalVideoId,
    this.videoStatus,
    this.videoPlaybackId,
    this.videoThumbnailUrl,
  });

  final String id;
  final String authorId;
  final String? authorUsername;
  final String body;
  final DateTime createdAt;
  final String mediaType;
  final List<String>? mediaUrls;

  /// design/system.md 1章 `posts.post_type`（normal | staked | battle_challenge）。
  final String postType;

  /// design/system.md 1章 `posts.staked_tp`。design/product.md 3.4節「ステーキング・ツイート」で
  /// 賭けたTP量。`postType == 'staked'` の場合のみ意味を持つ。
  final num stakedTp;

  /// design/system.md 5.3節。YouTube等の外部動画URL（原文のまま保持）。
  final String? externalVideoUrl;

  /// 外部動画の提供元。現状は `youtube` のみ。
  final String? externalVideoProvider;

  /// 埋め込み再生用に抽出したYouTube動画ID。
  final String? externalVideoId;

  /// design/system.md 1章 `videos.status`（pending | uploading | processing | ready | errored）。
  /// `mediaType == 'video'` の投稿にのみ紐づく。
  final String? videoStatus;

  /// design/system.md 5.2節。HLS再生用ID（`https://stream.mux.com/{id}.m3u8`）。
  final String? videoPlaybackId;

  /// design/system.md 5.2節。処理中プレースホルダー等に使うサムネイルURL。
  final String? videoThumbnailUrl;

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

    // `videos` は1投稿につき最大1本の想定（system.md 1章補足）。ネストselectは
    // 配列で返るため先頭要素のみ使用する。
    final rawVideos = map['videos'];
    Map? video;
    if (rawVideos is List && rawVideos.isNotEmpty) {
      video = rawVideos.first as Map;
    } else if (rawVideos is Map) {
      video = rawVideos;
    }

    return Post(
      id: map['id'] as String,
      authorId: map['author_id'] as String,
      authorUsername: username,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      mediaType: map['media_type'] as String? ?? 'text',
      mediaUrls: mediaUrls,
      authorIntellectPercentile: intellectPercentile,
      postType: map['post_type'] as String? ?? 'normal',
      stakedTp: map['staked_tp'] as num? ?? 0,
      externalVideoUrl: map['external_video_url'] as String?,
      externalVideoProvider: map['external_video_provider'] as String?,
      externalVideoId: map['external_video_id'] as String?,
      videoStatus: video?['status'] as String?,
      videoPlaybackId: video?['mux_playback_id'] as String?,
      videoThumbnailUrl: video?['thumbnail_url'] as String?,
    );
  }
}
