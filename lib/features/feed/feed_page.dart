import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_state.dart';
import '../quiz/quiz_controller.dart';
import 'feed_controller.dart';
import 'intellect_badge.dart';
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
      appBar: AppBar(
        title: const Text('Renga — フィード'),
        actions: [
          IconButton(
            tooltip: 'Discover',
            onPressed: () => context.go('/discover'),
            icon: const Icon(Icons.explore_outlined),
          ),
          if (currentUser != null) ...[
            IconButton(
              tooltip: '通知',
              onPressed: () => context.go('/notifications'),
              icon: const Icon(Icons.notifications_outlined),
            ),
            IconButton(
              tooltip: 'Battle（ロジックチェック）',
              onPressed: () => context.go('/battles'),
              icon: const Icon(Icons.sports_kabaddi_outlined),
            ),
            IconButton(
              tooltip: 'デイリークイズ',
              onPressed: () => context.go('/daily-quiz'),
              icon: const Icon(Icons.quiz_outlined),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (currentUser != null) const _OnboardingQuizBanner(),
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

/// design/product.md 3章「オンボーディングクイズ」。未完了のユーザーにのみ案内を表示する。
class _OnboardingQuizBanner extends ConsumerWidget {
  const _OnboardingQuizBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCompletedAsync = ref.watch(hasCompletedOnboardingProvider);

    return hasCompletedAsync.when(
      data: (hasCompleted) {
        if (hasCompleted) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('はじめてのクイズに挑戦しよう'),
            subtitle: const Text('3問に答えると暫定Intellectランクが決まります'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/onboarding-quiz'),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(width: 8),
              IntellectBadge(percentile: post.authorIntellectPercentile),
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
