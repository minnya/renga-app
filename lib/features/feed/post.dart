/// design/product.md 3.12節「引用リポスト」。引用元投稿の要約プレビュー（ミニカード）表示用の
/// 軽量モデル。`Post`本体と異なりエンゲージメント件数等は保持しない
/// （ミニカードでは不要なため、ネストselectのペイロードも最小限にしている）。
class QuotedPostPreview {
  const QuotedPostPreview({
    required this.id,
    required this.authorId,
    required this.authorUsername,
    required this.body,
    required this.mediaType,
    required this.mediaUrls,
    required this.createdAt,
    this.videoThumbnailUrl,
  });

  final String id;
  final String authorId;
  final String? authorUsername;
  final String body;
  final String mediaType;
  final List<String>? mediaUrls;
  final DateTime createdAt;
  final String? videoThumbnailUrl;

  /// `posts!quoted_post_id(...)` ネストselect結果からパースする。
  factory QuotedPostPreview.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    String? username;
    if (profile is Map) {
      username = profile['username'] as String?;
    }

    final rawMediaUrls = map['media_urls'];
    final mediaUrls = rawMediaUrls is List
        ? rawMediaUrls.map((e) => e as String).toList()
        : null;

    final rawVideos = map['videos'];
    Map? video;
    if (rawVideos is List && rawVideos.isNotEmpty) {
      video = rawVideos.first as Map;
    } else if (rawVideos is Map) {
      video = rawVideos;
    }

    return QuotedPostPreview(
      id: map['id'] as String,
      authorId: map['author_id'] as String,
      authorUsername: username,
      body: map['body'] as String? ?? '',
      mediaType: map['media_type'] as String? ?? 'text',
      mediaUrls: mediaUrls,
      createdAt: DateTime.parse(map['created_at'] as String),
      videoThumbnailUrl: video?['thumbnail_url'] as String?,
    );
  }

  /// [ComposeSheet]の引用リポストモードで、遷移元から渡された[Post]をそのまま
  /// ミニカードプレビュー表示するための変換。
  factory QuotedPostPreview.fromPost(Post post) {
    return QuotedPostPreview(
      id: post.id,
      authorId: post.authorId,
      authorUsername: post.authorUsername,
      body: post.body,
      mediaType: post.mediaType,
      mediaUrls: post.mediaUrls,
      createdAt: post.createdAt,
      videoThumbnailUrl: post.videoThumbnailUrl,
    );
  }
}

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
    required this.likeCount,
    required this.commentCount,
    required this.repostCount,
    this.externalVideoUrl,
    this.externalVideoProvider,
    this.externalVideoId,
    this.videoStatus,
    this.videoPlaybackId,
    this.videoThumbnailUrl,
    this.domainLabels,
    this.quotedPost,
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

  /// design/product.md 3.12節「基本エンゲージメント機能」。いいね件数。
  final int likeCount;

  /// design/product.md 3.12節。コメント件数。
  final int commentCount;

  /// design/product.md 3.12節。リポスト件数。
  final int repostCount;

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

  /// design/system.md 6.1節「ドメインラベリング」。`label_post_domain` Edge Functionが
  /// 投稿本文から自動付与した産業分類ラベル（日本標準産業分類の大分類キー、最大3件）。
  final List<String>? domainLabels;

  /// design/product.md 3.12節「引用リポスト」。引用元投稿の要約プレビュー。
  /// `posts.quoted_post_id`がnullの通常投稿では`null`。
  final QuotedPostPreview? quotedPost;

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

    final rawDomainLabels = map['domain_labels'];
    final domainLabels = rawDomainLabels is List && rawDomainLabels.isNotEmpty
        ? rawDomainLabels.map((e) => e as String).toList()
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

    // design/product.md 3.12節「引用リポスト」。`posts!quoted_post_id(...)`ネストselectは
    // 単一行（1:1）想定だが、Supabase Dartの実装により配列/Mapどちらでも返り得るため防御的に扱う。
    final rawQuotedPost = map['quoted_post'];
    Map<String, dynamic>? quotedPostMap;
    if (rawQuotedPost is List && rawQuotedPost.isNotEmpty) {
      quotedPostMap = Map<String, dynamic>.from(rawQuotedPost.first as Map);
    } else if (rawQuotedPost is Map) {
      quotedPostMap = Map<String, dynamic>.from(rawQuotedPost);
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
      likeCount: _parseAggregateCount(map['likes']),
      commentCount: _parseAggregateCount(map['comments']),
      repostCount: _parseAggregateCount(map['reposts']),
      externalVideoUrl: map['external_video_url'] as String?,
      externalVideoProvider: map['external_video_provider'] as String?,
      externalVideoId: map['external_video_id'] as String?,
      videoStatus: video?['status'] as String?,
      videoPlaybackId: video?['mux_playback_id'] as String?,
      videoThumbnailUrl: video?['thumbnail_url'] as String?,
      domainLabels: domainLabels,
      quotedPost: quotedPostMap == null
          ? null
          : QuotedPostPreview.fromMap(quotedPostMap),
    );
  }

  /// Supabase PostgRESTの集計embed（例: `likes(count)`）は
  /// `[{"count": N}]` という形の配列で返るため、防御的にパースする。
  static int _parseAggregateCount(dynamic value) {
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map && first['count'] != null) {
        return (first['count'] as num).toInt();
      }
    }
    return 0;
  }
}
