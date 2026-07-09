import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../quiz/quiz_controller.dart';
import '../discover/discover_controller.dart' show domainDisplayLabel;
import 'comments_sheet.dart';
import 'feed_controller.dart';
import 'fullscreen_media_viewer.dart';
import 'intellect_badge.dart';
import 'media_carousel.dart';
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
    // design/product.md 3.15節「デイリーミッションの受験可否・クールダウン表示」。
    final hasCompletedDailyToday = ref.watch(hasCompletedDailyTodayProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedAppBarTitle),
        // design/product.md 4章: Discover/BattleはボトムナビゲーションのタブになったためAppBarから撤去。
        actions: [
          if (currentUser != null) ...[
            IconButton(
              tooltip: 'メッセージ',
              onPressed: () => context.push('/messages'),
              icon: const Icon(Icons.chat_bubble_outline),
            ),
            IconButton(
              tooltip: '通知',
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_outlined),
            ),
            if (hasCompletedDailyToday) ...[
              const _DailyQuizCooldownLabel(),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: hasCompletedDailyToday ? l10n.feedDailyQuizCompletedTooltip : l10n.feedDailyQuizTooltip,
              onPressed: hasCompletedDailyToday ? null : () => context.push('/daily-quiz'),
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

/// design/product.md 3.15節「デイリーミッションの受験可否・クールダウン表示」。
/// UTC0時までの残り時間を`HH:mm`形式で1分ごとに更新表示する。
class _DailyQuizCooldownLabel extends StatefulWidget {
  const _DailyQuizCooldownLabel();

  @override
  State<_DailyQuizCooldownLabel> createState() => _DailyQuizCooldownLabelState();
}

class _DailyQuizCooldownLabelState extends State<_DailyQuizCooldownLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatRemaining() {
    final nowUtc = DateTime.now().toUtc();
    final nextResetUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day).add(const Duration(days: 1));
    final remaining = nextResetUtc.difference(nowUtc);
    final hours = remaining.inHours.toString().padLeft(2, '0');
    final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Text(
          '${l10n.feedDailyQuizCooldownLabel} ${_formatRemaining()}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
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
            title: Text(AppLocalizations.of(context).feedOnboardingBannerTitle),
            subtitle: Text(AppLocalizations.of(context).feedOnboardingBannerSubtitle),
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

/// アクションバーのボタン（いいね・コメント・リポスト・共有用）。
/// Instagram/X風のシンプルなアイコンボタン。
class _ActionBarButton extends StatelessWidget {
  const _ActionBarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: effectiveColor),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: effectiveColor),
          ),
        ],
      ),
    );
  }
}


class _PostTile extends ConsumerStatefulWidget {
  const _PostTile({required this.post});

  final Post post;

  @override
  ConsumerState<_PostTile> createState() => _PostTileState();
}

class _PostTileState extends ConsumerState<_PostTile> {
  YoutubePlayerController? _youtubeController;

  /// design/product.md 3.13節「動画の自動再生（スクロールイン）」。
  /// 動画が画面内に一定割合入っている間だけtrueにし、ミュート自動再生する。
  bool _videoVisible = false;

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

  /// design/product.md 3.12節「いいね」。楽観的なトグル。
  Future<void> _handleToggleLike(bool currentlyLiked) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(feedControllerProvider).toggleLike(
            postId: post.id,
            currentlyLiked: currentlyLiked,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.feedLikeError('$e'))),
      );
    }
  }

  /// design/product.md 3.12節「リポスト」。
  Future<void> _handleToggleRepost(bool currentlyReposted) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(feedControllerProvider).toggleRepost(
            postId: post.id,
            currentlyReposted: currentlyReposted,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.feedRepostError('$e'))),
      );
    }
  }

  /// design/product.md 3.12節「コメント」。ボトムシートでコメント一覧・投稿フォームを表示する。
  void _handleOpenComments() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CommentsBottomSheet(postId: post.id),
    );
  }

  /// design/product.md 3.13節「タップで全画面表示」。共通の全画面メディアビューアを開く。
  void _openFullscreenImage(List<String> imageUrls, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenMediaViewer(
          imageUrls: imageUrls,
          initialImageIndex: index,
        ),
      ),
    );
  }

  void _openFullscreenVideo(String playbackId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenMediaViewer(videoPlaybackId: playbackId),
      ),
    );
  }

  /// design/product.md 3.12節「共有」。OS標準の共有シートを開く。
  Future<void> _handleShare() async {
    final buffer = StringBuffer(post.body);
    if (post.mediaUrls != null && post.mediaUrls!.isNotEmpty) {
      buffer.write('\n${post.mediaUrls!.first}');
    } else if (post.externalVideoUrl != null) {
      buffer.write('\n${post.externalVideoUrl}');
    }
    await SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  @override
  Widget build(BuildContext context) {
    final imageUrls = post.mediaType == 'image' && (post.mediaUrls?.isNotEmpty ?? false)
        ? post.mediaUrls!
        : null;
    final l10n = AppLocalizations.of(context);

    final authorName = post.authorUsername ?? l10n.feedUnknownUser;
    final firstLetter = authorName.isNotEmpty ? authorName[0].toUpperCase() : '?';

    final likedIds = ref.watch(myLikedPostIdsProvider).value ?? const <String>{};
    final repostedIds = ref.watch(myRepostedPostIdsProvider).value ?? const <String>{};
    final isLiked = likedIds.contains(post.id);
    final isReposted = repostedIds.contains(post.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar + Username + Created At
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.primary.withAlpha((0.3 * 255).toInt()),
                child: Text(
                  firstLetter,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Metadata row: Badge + Staked TP (if applicable)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        IntellectBadge(percentile: post.authorIntellectPercentile),
                        if (post.postType == 'staked')
                          Chip(
                            avatar: const Icon(Icons.bolt, size: 14),
                            label: Text(
                              l10n.feedStakedTpLabel(post.stakedTp as int),
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatCreatedAt(post.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Post body text
          if (post.body.isNotEmpty) ...[
            Text(
              post.body,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
          ],
          // design/system.md 6.1節「ドメインラベリング」。AIが自動付与した産業分類タグ。
          if (post.domainLabels != null && post.domainLabels!.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: post.domainLabels!.map((label) {
                return Chip(
                  avatar: const Icon(Icons.auto_awesome, size: 14),
                  label: Text(domainDisplayLabel(label), style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          // Image media（design/product.md 3.13節: 複数画像は横スクロール＋ドットインジケーター）
          if (imageUrls != null) ...[
            ImageCarousel(
              imageUrls: imageUrls,
              onTapImage: (index) => _openFullscreenImage(imageUrls, index),
            ),
            const SizedBox(height: 12),
          ],
          // YouTube player
          if (_youtubeController != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: YoutubePlayer(controller: _youtubeController!),
            ),
            const SizedBox(height: 12),
          ],
          // Mux video player（design/product.md 3.13節: スクロールイン自動再生・全画面表示）
          if (post.mediaType == 'video') ...[
            post.videoStatus == 'ready' && post.videoPlaybackId != null
                ? VisibilityDetector(
                    key: ValueKey('video-visibility-${post.id}'),
                    onVisibilityChanged: (info) {
                      final visible = info.visibleFraction > 0.6;
                      if (visible != _videoVisible && mounted) {
                        setState(() => _videoVisible = visible);
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: MuxVideoPlayerWidget(
                        playbackId: post.videoPlaybackId!,
                        autoPlay: _videoVisible,
                        isPreview: true,
                        showFullscreenButton: true,
                        onFullscreenTap: () => _openFullscreenVideo(post.videoPlaybackId!),
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: VideoProcessingPlaceholder(
                      thumbnailUrl: post.videoThumbnailUrl,
                      status: post.videoStatus ?? 'pending',
                    ),
                  ),
            const SizedBox(height: 12),
          ],
          // Action bar: Like, Comment, Repost, Share
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ActionBarButton(
                icon: isLiked ? Icons.favorite : Icons.favorite_border,
                label: post.likeCount > 0 ? '${post.likeCount}' : l10n.feedActionLike,
                color: isLiked ? Colors.red : null,
                onPressed: () => _handleToggleLike(isLiked),
              ),
              _ActionBarButton(
                icon: Icons.chat_bubble_outline,
                label: post.commentCount > 0 ? '${post.commentCount}' : l10n.feedActionComment,
                onPressed: _handleOpenComments,
              ),
              _ActionBarButton(
                icon: Icons.repeat,
                label: post.repostCount > 0 ? '${post.repostCount}' : l10n.feedActionRepost,
                color: isReposted ? Colors.green : null,
                onPressed: () => _handleToggleRepost(isReposted),
              ),
              _ActionBarButton(
                icon: Icons.share_outlined,
                label: l10n.feedActionShare,
                onPressed: _handleShare,
              ),
            ],
          ),
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
