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
    final postsAsync = ref.watch(filteredFeedPostsProvider);
    final currentUser = ref.watch(currentUserProvider);
    final layer = ref.watch(layerFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Renga — フィード')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<LayerFilter>(
              segments: const [
                ButtonSegment(value: LayerFilter.all, label: Text('全ユーザー')),
                ButtonSegment(value: LayerFilter.top25, label: Text('上位25%')),
                ButtonSegment(value: LayerFilter.top5, label: Text('上位5%')),
              ],
              selected: {layer},
              onSelectionChanged: (selection) {
                ref.read(layerFilterProvider.notifier).state = selection.first;
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
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
          ),
        ],
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

/// design/product.md 4章「上位25%/5%知能バッジ」。値が小さいほど上位を表す前提。
String? _intellectBadgeLabel(num? percentile) {
  if (percentile == null) return null;
  if (percentile <= 5) return '上位5%';
  if (percentile <= 25) return '上位25%';
  return null;
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final badgeLabel = _intellectBadgeLabel(post.authorIntellectPercentile);
    final imageUrl = post.mediaType == 'image' && (post.mediaUrls?.isNotEmpty ?? false)
        ? post.mediaUrls!.first
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  post.authorUsername ?? '不明なユーザー',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (badgeLabel != null) ...[
                const SizedBox(width: 8),
                Chip(
                  label: Text(badgeLabel, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
              const SizedBox(width: 8),
              Text(
                _formatCreatedAt(post.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (post.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(post.body),
          ],
          if (imageUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox(height: 80, child: Center(child: Text('画像を読み込めませんでした'))),
              ),
            ),
          ],
        ],
      ),
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
