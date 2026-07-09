import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_state.dart';
import '../../core/firebase_client.dart';
import '../../core/supabase_client.dart';
import 'comment.dart';
import 'post.dart';
import 'youtube_utils.dart';

/// design/product.md 4章の「レイヤーフィルター」（全ユーザー/上位25%/上位5%）。
enum LayerFilter { all, top25, top5 }

/// [LayerFilter] <-> `profiles.default_layer_filter`（text列、
/// `supabase/migrations/20260708090000_add_default_layer_filter.sql`）・
/// SharedPreferencesの文字列表現の相互変換。
extension LayerFilterCodec on LayerFilter {
  String toDbValue() => switch (this) {
    LayerFilter.all => 'all',
    LayerFilter.top25 => 'top25',
    LayerFilter.top5 => 'top5',
  };

  static LayerFilter fromDbValue(String? value) => switch (value) {
    'top25' => LayerFilter.top25,
    'top5' => LayerFilter.top5,
    _ => LayerFilter.all,
  };
}

/// SharedPreferencesに保存する際のキー。
const _kLayerFilterPrefsKey = 'layer_filter';

/// 現在選択中のレイヤーフィルター（design/product.md 3.3節）。
///
/// 設計方針:
/// - 起動直後はまずSharedPreferencesのローカル値を反映する。`build()`自体は同期的に
///   `LayerFilter.all`を返し、その直後に非同期でローカル値を読み込んで`state`へ反映する
///   （オフラインでも即座に選択状態を表示できるようにするため、`build()`をasyncにせず
///   `Notifier`＋fire-and-forgetの初期ロードとしている）。
/// - ログイン中であれば続けてバックグラウンドで`profiles.default_layer_filter`を取得し、
///   ローカル値と異なる場合はアカウント側の値を優先して採用する。複数端末間で同期させる
///   ことを優先し、「直近のローカル選択」より「アカウントに同期済みの値」を正とするシンプルな
///   方針とした（アカウント値が存在しない/取得失敗時はローカル値をそのまま維持）。
/// - ログイン状態が変化した（別アカウントでログインした）場合も同様にアカウント側の値へ
///   同期し直す。
/// - ユーザーが明示的に変更した場合（[select]）は、SharedPreferencesへの書き込みと、
///   ログイン中なら`profiles`テーブルへのupdateの両方を行う。
class LayerFilterNotifier extends Notifier<LayerFilter> {
  @override
  LayerFilter build() {
    // ログインユーザーが切り替わったら（null→ユーザー、または別ユーザー）アカウント側の値へ
    // 同期し直す。
    ref.listen<User?>(currentUserProvider, (previous, next) {
      if (next != null && next.id != previous?.id) {
        _syncFromAccount(next.id);
      }
    });

    // ignore: discarded_futures
    _loadInitial();
    return LayerFilter.all;
  }

  Future<void> _loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final localValue = LayerFilterCodec.fromDbValue(prefs.getString(_kLayerFilterPrefsKey));
    state = localValue;

    final user = supabase.auth.currentUser;
    if (user != null) {
      await _syncFromAccount(user.id, prefs: prefs);
    }
  }

  /// ログイン中のアカウントが持つ`profiles.default_layer_filter`を取得し、現在の`state`と
  /// 異なればアカウント側の値を採用してローカルにも書き戻す。
  Future<void> _syncFromAccount(String userId, {SharedPreferences? prefs}) async {
    try {
      final row = await supabase
          .from('profiles')
          .select('default_layer_filter')
          .eq('id', userId)
          .maybeSingle();
      final remoteRaw = row?['default_layer_filter'] as String?;
      if (remoteRaw == null) return;

      final remoteValue = LayerFilterCodec.fromDbValue(remoteRaw);
      if (remoteValue != state) {
        state = remoteValue;
        final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
        await resolvedPrefs.setString(_kLayerFilterPrefsKey, remoteValue.toDbValue());
      }
    } catch (_) {
      // オフライン等でアカウント側の取得に失敗してもローカル値の表示は継続する。
    }
  }

  /// ユーザーがフィルターを変更した際に呼ぶ。ローカル保存＋（ログイン中のみ）
  /// アカウント側の`profiles.default_layer_filter`への同期の両方を行う。
  Future<void> select(LayerFilter filter) async {
    state = filter;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLayerFilterPrefsKey, filter.toDbValue());

    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('profiles')
          .update({'default_layer_filter': filter.toDbValue()})
          .eq('id', user.id);
    } catch (_) {
      // ネットワークエラー等でアカウント同期に失敗してもローカルの選択状態は維持する。
    }
  }
}

/// 現在選択中のレイヤーフィルター。
final layerFilterProvider = NotifierProvider<LayerFilterNotifier, LayerFilter>(
  LayerFilterNotifier.new,
);

/// design/system.md 1章の `posts` テーブルから投稿一覧（作成日時降順・最大50件）を取得する。
///
/// 投稿者の `username` / `intellect_percentile` も併せて取得するため、Supabase Dartの
/// ネストselectで `profiles(username, intellect_percentile)` を同時取得する。
/// `posts` は誰でもselect可能なRLSのため、未ログインでも取得できる。
final feedPostsProvider = FutureProvider<List<Post>>((ref) async {
  final rows = await supabase
      .from('posts')
      .select(
        'id, body, created_at, author_id, media_type, media_urls, post_type, staked_tp, '
        'domain_labels, quoted_post_id, '
        'external_video_url, external_video_provider, external_video_id, '
        'profiles(username, intellect_percentile), '
        'videos(status, mux_playback_id, thumbnail_url), '
        'likes(count), comments(count), reposts(count), '
        'quoted_post:posts!quoted_post_id(id, body, media_type, media_urls, author_id, '
        'created_at, profiles(username), videos(thumbnail_url))',
      )
      .order('created_at', ascending: false)
      .limit(50);

  return rows.map((row) => Post.fromMap(row)).toList();
});

/// design/product.md 3.12節「投稿詳細（スレッド表示）」。投稿1件を単独取得する
/// （フィード一覧に無い場合、例えばDiscover経由でも詳細画面を開けるようにするため）。
final postByIdProvider = FutureProvider.family<Post, String>((ref, postId) async {
  final row = await supabase
      .from('posts')
      .select(
        'id, body, created_at, author_id, media_type, media_urls, post_type, staked_tp, '
        'domain_labels, quoted_post_id, '
        'external_video_url, external_video_provider, external_video_id, '
        'profiles(username, intellect_percentile), '
        'videos(status, mux_playback_id, thumbnail_url), '
        'likes(count), comments(count), reposts(count), '
        'quoted_post:posts!quoted_post_id(id, body, media_type, media_urls, author_id, '
        'created_at, profiles(username), videos(thumbnail_url))',
      )
      .eq('id', postId)
      .single();

  return Post.fromMap(row);
});

/// [layerFilterProvider] の選択に応じて [feedPostsProvider] の結果を絞り込む。
///
/// データ規模が小さいMVPのため、サーバー側クエリを複雑にせずクライアント側でフィルタする。
/// パーセンタイル自動再計算バッチ（design/system.md 12章、Phase3）が未実装のため、
/// 現状は全ユーザーの`intellect_percentile`が`0`のままとなり、絞り込んでも見た目上の差は出ない。
final filteredFeedPostsProvider = Provider<AsyncValue<List<Post>>>((ref) {
  final postsAsync = ref.watch(feedPostsProvider);
  final layer = ref.watch(layerFilterProvider);

  return postsAsync.whenData((posts) {
    return switch (layer) {
      LayerFilter.all => posts,
      LayerFilter.top25 => posts.where((p) => (p.authorIntellectPercentile ?? 100) <= 25).toList(),
      LayerFilter.top5 => posts.where((p) => (p.authorIntellectPercentile ?? 100) <= 5).toList(),
    };
  });
});

/// design/product.md 3.12節。ログインユーザーが「いいね」済みの投稿ID集合。
final myLikedPostIdsProvider = FutureProvider<Set<String>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return {};
  final rows = await supabase.from('likes').select('post_id').eq('user_id', user.id);
  return rows.map((row) => row['post_id'] as String).toSet();
});

/// design/product.md 3.12節。ログインユーザーがリポスト済みの投稿ID集合。
final myRepostedPostIdsProvider = FutureProvider<Set<String>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return {};
  final rows = await supabase.from('reposts').select('post_id').eq('user_id', user.id);
  return rows.map((row) => row['post_id'] as String).toSet();
});

/// design/product.md 3.12節。投稿へのコメント一覧（作成日時昇順）。
///
/// フラットに全件（トップレベル＋返信）を取得し、`parent_comment_id`によるグルーピングは
/// UI側（[CommentsBottomSheet]）で行う。返信は1階層のみのため、これで十分。
final commentsProvider = FutureProvider.family<List<Comment>, String>((ref, postId) async {
  final rows = await supabase
      .from('comments')
      .select(
        'id, post_id, author_id, body, created_at, parent_comment_id, media_urls, '
        'external_video_url, profiles(username, avatar_url)',
      )
      .eq('post_id', postId)
      .order('created_at');
  return rows.map((row) => Comment.fromMap(row)).toList();
});

/// 投稿・画像アップロードを行うコントローラ。
///
/// 作成後は [feedPostsProvider] を無効化し、一覧を再取得させる。
class FeedController {
  FeedController(this.ref);

  final Ref ref;

  /// [quotedPostId] を指定すると design/product.md 3.12節「引用リポスト」として、
  /// `posts.quoted_post_id` に引用元投稿のIDをセットして投稿する
  /// （`ComposeSheet`の引用リポストモードから呼ばれる）。
  Future<void> createTextPost({
    required String authorId,
    required String body,
    String? quotedPostId,
  }) async {
    final trimmed = body.trim();
    // design/product.md 3.12節「引用リポスト」: 引用元投稿自体が本文の役割を持つため、
    // 引用リポスト時（quotedPostId指定時）は本文が空でも許可する。
    if (trimmed.isEmpty && quotedPostId == null) {
      throw ArgumentError('投稿内容を入力してください');
    }

    final row = await supabase
        .from('posts')
        .insert({
          'author_id': authorId,
          'body': trimmed,
          'media_type': containsYoutubeUrl(trimmed) ? 'youtube_embed' : 'text',
          if (quotedPostId != null) 'quoted_post_id': quotedPostId,
          ..._youtubeFields(trimmed),
        })
        .select('id')
        .single();

    ref.invalidate(feedPostsProvider);
    _labelPostDomain(row['id'] as String, trimmed);
    await _logPostCreated(quotedPostId != null ? 'quote_repost' : 'text');
  }

  /// design/system.md 6.1節「ドメインラベリング」。投稿本文をGeminiで分類し
  /// posts.domain_labels に反映する（Discoverページでのドメイン別表示に使う）。
  /// ベストエフォートのため失敗しても投稿作成自体には影響させない。
  void _labelPostDomain(String postId, String body) {
    if (body.trim().length < 20) return;
    // ignore: discarded_futures
    _invokeLabelPostDomain(postId, body);
  }

  Future<void> _invokeLabelPostDomain(String postId, String body) async {
    try {
      await supabase.functions.invoke(
        'label_post_domain',
        body: {'post_id': postId, 'text': body},
      );
    } catch (error) {
      // ignore: avoid_print
      print('label_post_domain failed: $error');
    }
  }

  /// design/system.md 5.3節。本文からYouTube URLを検出し、`posts` に保存する
  /// `external_video_*` 列の値を組み立てる。YouTube URLが含まれない場合は空Map。
  Map<String, dynamic> _youtubeFields(String body) {
    final videoId = extractYoutubeVideoId(body);
    if (videoId == null) return {};
    return {
      'external_video_url': extractYoutubeUrl(body),
      'external_video_provider': 'youtube',
      'external_video_id': videoId,
    };
  }

  /// design/system.md 5章の画像投稿。`post-images` バケットの `{userId}/{fileName}` に
  /// アップロードし、公開URLを `posts.media_urls` へ保存する。
  Future<String> uploadPostImage({
    required String userId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final uniqueName =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 31)}.$fileExt';
    final path = '$userId/$uniqueName';

    await supabase.storage.from('post-images').uploadBinary(path, bytes);
    return supabase.storage.from('post-images').getPublicUrl(path);
  }

  Future<void> createImagePost({
    required String authorId,
    required String body,
    required String imageUrl,
    String? quotedPostId,
  }) async {
    final trimmedBody = body.trim();
    final row = await supabase
        .from('posts')
        .insert({
          'author_id': authorId,
          'body': trimmedBody,
          'media_type': 'image',
          'media_urls': [imageUrl],
          if (quotedPostId != null) 'quoted_post_id': quotedPostId,
        })
        .select('id')
        .single();

    ref.invalidate(feedPostsProvider);
    _labelPostDomain(row['id'] as String, trimmedBody);
    await _logPostCreated(quotedPostId != null ? 'quote_repost' : 'image');
  }

  /// design/system.md 5章「Mux動画アーキテクチャ」。動画アップロード開始時に
  /// `posts` レコードを先に作成し、返却された `post_id` に紐づけて `videos` テーブルへ
  /// アップロード状況を記録できるようにする（[VideoUploadController]から呼び出す）。
  Future<String> createVideoPost({
    required String authorId,
    required String body,
    String? quotedPostId,
  }) async {
    final row = await supabase
        .from('posts')
        .insert({
          'author_id': authorId,
          'body': body.trim(),
          'media_type': 'video',
          if (quotedPostId != null) 'quoted_post_id': quotedPostId,
        })
        .select('id')
        .single();

    ref.invalidate(feedPostsProvider);
    final postId = row['id'] as String;
    final trimmedBody = body.trim();
    if (trimmedBody.isNotEmpty) {
      _labelPostDomain(postId, trimmedBody);
    }
    return postId;
  }

  /// design/product.md 3.4節「ステーキング・ツイート: 投稿時にTPを賭ける」。
  /// design/system.md 7章のロック解除クイズ通過が前提。TPの減算と投稿作成を
  /// `create_staked_post` RPC（`supabase/migrations/*_add_staking_functions.sql`）内で
  /// アトミックに行い、残高不足時はDB側の例外で投稿をブロックする。
  Future<void> createStakedPost({required String body, required num stakedTp}) async {
    await supabase.rpc(
      'create_staked_post',
      params: {'p_body': body.trim(), 'p_staked_tp': stakedTp},
    );

    ref.invalidate(feedPostsProvider);
    await _logPostCreated('staked');
  }

  /// design/product.md 3.12節「いいね」。トグル式（再タップで取り消し）。
  Future<void> toggleLike({required String postId, required bool currentlyLiked}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (currentlyLiked) {
      await supabase.from('likes').delete().eq('post_id', postId).eq('user_id', user.id);
    } else {
      await supabase.from('likes').insert({'post_id': postId, 'user_id': user.id});
    }

    ref.invalidate(feedPostsProvider);
    ref.invalidate(myLikedPostIdsProvider);
  }

  /// design/product.md 3.12節「リポスト」。トグル式（再タップで取り消し）。
  Future<void> toggleRepost({required String postId, required bool currentlyReposted}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (currentlyReposted) {
      await supabase.from('reposts').delete().eq('post_id', postId).eq('user_id', user.id);
    } else {
      await supabase.from('reposts').insert({
        'post_id': postId,
        'user_id': user.id,
        'acknowledged_warning': true,
      });
    }

    ref.invalidate(feedPostsProvider);
    ref.invalidate(myRepostedPostIdsProvider);
  }

  /// design/product.md 3.12節「コメント」「返信（スレッド化）」。
  ///
  /// [parentCommentId] を指定すると当該コメントへの返信として投稿する（1階層のみ）。
  /// [mediaUrls] は事前に [uploadCommentImage] でアップロード済みの画像URL一覧。
  /// 動画添付（Mux）は本文投稿とは別に、戻り値の `comments.id` を使って
  /// `VideoUploadController.uploadVideo(commentId: ...)` を呼び出す2段階フローとなる
  /// （[createVideoPost]と同様のパターン）。
  ///
  /// 戻り値は作成された `comments.id`（動画添付フローで利用するため）。未ログイン・本文空の
  /// 場合は`null`を返す。
  Future<String?> addComment({
    required String postId,
    required String body,
    String? parentCommentId,
    List<String>? mediaUrls,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    final trimmed = body.trim();
    if (trimmed.isEmpty && (mediaUrls == null || mediaUrls.isEmpty)) return null;

    final row = await supabase
        .from('comments')
        .insert({
          'post_id': postId,
          'author_id': user.id,
          'body': trimmed,
          if (parentCommentId != null) 'parent_comment_id': parentCommentId,
          if (mediaUrls != null && mediaUrls.isNotEmpty) 'media_urls': mediaUrls,
        })
        .select('id')
        .single();

    ref.invalidate(commentsProvider(postId));
    ref.invalidate(feedPostsProvider);

    return row['id'] as String;
  }

  /// design/system.md 5章の画像投稿と同じ`post-images`バケットを流用した、
  /// コメント・返信への画像添付アップロード。
  Future<String> uploadCommentImage({
    required String userId,
    required Uint8List bytes,
    required String fileExt,
  }) {
    return uploadPostImage(userId: userId, bytes: bytes, fileExt: fileExt);
  }

  /// design/system.md 4章「Analytics」の主要アクション計測。投稿種別を`post_type`
  /// パラメータとして送信する。
  Future<void> _logPostCreated(String postType) {
    return ref.read(firebaseAnalyticsProvider).logEvent(
      name: 'post_created',
      parameters: {'post_type': postType},
    );
  }
}

final feedControllerProvider = Provider<FeedController>((ref) {
  return FeedController(ref);
});
