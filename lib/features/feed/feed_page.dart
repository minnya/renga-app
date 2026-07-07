import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_state.dart';
import 'feed_controller.dart';
import 'post.dart';

/// design/system.md のフィード画面。投稿一覧を表示する。
///
/// `posts` は誰でもselect可能なRLSのため、未ログインでも閲覧できる。
/// 投稿作成（`/compose` への遷移）はログイン中のみ可能。
class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(feedPostsProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Renga — フィード')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(feedPostsProvider);
          await ref.read(feedPostsProvider.future);
        },
        child: postsAsync.when(
          data: (posts) {
            if (posts.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('まだ投稿がありません')),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: posts.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) => _PostTile(post: posts[index]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text('投稿の取得に失敗しました: $error')),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: currentUser != null
          ? FloatingActionButton(
              onPressed: () => context.go('/compose'),
              child: const Icon(Icons.edit),
            )
          : null,
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(post.authorUsername ?? '不明なユーザー'),
      subtitle: Text(post.body),
      trailing: Text(
        _formatCreatedAt(post.createdAt),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      isThreeLine: post.body.length > 40,
    );
  }

  String _formatCreatedAt(DateTime dateTime) {
    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}
