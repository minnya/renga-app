import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import 'post.dart';

/// design/system.md 1章の `posts` テーブルから投稿一覧（作成日時降順・最大50件）を取得する。
///
/// 投稿者の `username` も併せて表示するため、Supabase Dartのネストselectで
/// `profiles(username)` を同時取得する。`posts` は誰でもselect可能なRLSのため、
/// 未ログインでも取得できる。
final feedPostsProvider = FutureProvider<List<Post>>((ref) async {
  final rows = await supabase
      .from('posts')
      .select('id, body, created_at, author_id, profiles(username)')
      .order('created_at', ascending: false)
      .limit(50);

  return rows.map((row) => Post.fromMap(row)).toList();
});

/// 新規テキスト投稿を作成する。
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
}

final feedControllerProvider = Provider<FeedController>((ref) {
  return FeedController(ref);
});
