import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_state.dart';
import '../../core/firebase_client.dart';
import '../../core/supabase_client.dart';
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
        'external_video_url, external_video_provider, external_video_id, '
        'profiles(username, intellect_percentile), '
        'videos(status, mux_playback_id, thumbnail_url)',
      )
      .order('created_at', ascending: false)
      .limit(50);

  return rows.map((row) => Post.fromMap(row)).toList();
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

/// 投稿・画像アップロードを行うコントローラ。
///
/// 作成後は [feedPostsProvider] を無効化し、一覧を再取得させる。
class FeedController {
  FeedController(this.ref);

  final Ref ref;

  Future<void> createTextPost({required String authorId, required String body}) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('投稿内容を入力してください');
    }

    await supabase.from('posts').insert({
      'author_id': authorId,
      'body': trimmed,
      'media_type': containsYoutubeUrl(trimmed) ? 'youtube_embed' : 'text',
      ..._youtubeFields(trimmed),
    });

    ref.invalidate(feedPostsProvider);
    await _logPostCreated('text');
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
  }) async {
    await supabase.from('posts').insert({
      'author_id': authorId,
      'body': body.trim(),
      'media_type': 'image',
      'media_urls': [imageUrl],
    });

    ref.invalidate(feedPostsProvider);
    await _logPostCreated('image');
  }

  /// design/system.md 5章「Mux動画アーキテクチャ」。動画アップロード開始時に
  /// `posts` レコードを先に作成し、返却された `post_id` に紐づけて `videos` テーブルへ
  /// アップロード状況を記録できるようにする（[VideoUploadController]から呼び出す）。
  Future<String> createVideoPost({required String authorId, required String body}) async {
    final row = await supabase
        .from('posts')
        .insert({
          'author_id': authorId,
          'body': body.trim(),
          'media_type': 'video',
        })
        .select('id')
        .single();

    ref.invalidate(feedPostsProvider);
    return row['id'] as String;
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
