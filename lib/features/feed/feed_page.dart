import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../quiz/quiz_controller.dart';
import 'feed_controller.dart';
import 'intellect_badge.dart';
import 'native_ad_tile.dart';
import 'post.dart';
import 'video_player_widget.dart';

/// design/system.md 10章「マネタイズ（AdMob）実装」。投稿10件ごとにネイティブ広告を差し込む間隔。
const _kNativeAdInterval = 10;

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
    // design/system.md 9章「Flutterアプリ構成」: 文言はAppLocalizations経由で取得する（gen-l10n生成）。
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedAppBarTitle),
        // design/product.md 4章: Discover/BattleはボトムナビゲーションのタブになったためAppBarから撤去。
        actions: [
          if (currentUser != null) ...[
            IconButton(
              tooltip: '通知',
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_outlined),
            ),
            IconButton(
              tooltip: l10n.feedDailyQuizTooltip,
              onPressed: () => context.push('/daily-quiz'),
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
              segments: [
                ButtonSegment(value: LayerFilter.all, label: Text(l10n.feedFilterAll)),
                ButtonSegment(value: LayerFilter.top25, label: Text(l10n.feedFilterTop25)),
                ButtonSegment(value: LayerFilter.top5, label: Text(l10n.feedFilterTop5)),
              ],
              selected: {layer},
              onSelectionChanged: (selection) {
                ref.read(layerFilterProvider.notifier).select(selection.first);
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
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text(l10n.feedEmpty)),
                        ),
                      ],
                    );
                  }
                  // 投稿10件ごとにネイティブ広告を1件差し込む（design/system.md 10章）。
                  final adCount = posts.length ~/ _kNativeAdInterval;
                  final itemCount = posts.length + adCount;
                  const blockSize = _kNativeAdInterval + 1;

                  return ListView.separated(
                    itemCount: itemCount,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final isAdSlot = (index + 1) % blockSize == 0;
                      if (isAdSlot) {
                        return const NativeAdTile();
                      }
                      final postIndex = index - (index ~/ blockSize);
                      return _PostTile(post: posts[postIndex]);
                    },
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
      // design/product.md 4章: 投稿作成はボトムナビゲーション中央のComposeタブに統一したため、
      // Feed画面独自のFABは撤去する（X/Instagram同様、投稿導線をボトムナビに一本化）。
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

class _PostTile extends StatefulWidget {
  const _PostTile({required this.post});

  final Post post;

  @override
  State<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<_PostTile> {
  YoutubePlayerController? _youtubeController;

  Post get post => widget.post;

  @override
  void initState() {
    super.initState();
    final videoId = post.externalVideoId;
    if (post.externalVideoProvider == 'youtube' && videoId != null) {
      _youtubeController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(autoPlay: false, mute: false),
      );
    }
  }

  @override
  void dispose() {
    _youtubeController?.dispose();
    super.dispose();
  }

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
              if (post.postType == 'staked') ...[
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.bolt, size: 14),
                  label: Text('賭けTP: ${post.stakedTp}', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
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
          if (_youtubeController != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: YoutubePlayer(controller: _youtubeController!),
            ),
          ],
          if (post.mediaType == 'video') ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: post.videoStatus == 'ready' && post.videoPlaybackId != null
                  ? MuxVideoPlayerWidget(playbackId: post.videoPlaybackId!)
                  : VideoProcessingPlaceholder(
                      thumbnailUrl: post.videoThumbnailUrl,
                      status: post.videoStatus ?? 'pending',
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
