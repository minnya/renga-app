import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/supabase_client.dart';
import 'post.dart';

/// design/product.md 4章の「レイヤーフィルター」（全ユーザー/上位25%/上位5%）。
enum LayerFilter { all, top25, top5 }

/// 現在選択中のレイヤーフィルター。
final layerFilterProvider = StateProvider<LayerFilter>((ref) => LayerFilter.all);

/// design/system.md 1章の `posts` テーブルから投稿一覧（作成日時降順・最大50件）を取得する。
///
/// 投稿者の `username` / `intellect_percentile` も併せて取得するため、Supabase Dartの
/// ネストselectで `profiles(username, intellect_percentile)` を同時取得する。
/// `posts` は誰でもselect可能なRLSのため、未ログインでも取得できる。
final feedPostsProvider = FutureProvider<List<Post>>((ref) async {
  final rows = await supabase
      .from('posts')
      .select(
        'id, body, created_at, author_id, media_type, media_urls, '
        'profiles(username, intellect_percentile)',
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
      'media_type': 'text',
    });

    ref.invalidate(feedPostsProvider);
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
  }
}

final feedControllerProvider = Provider<FeedController>((ref) {
  return FeedController(ref);
});
