import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/time_format.dart';
import '../quiz/quiz_controller.dart';
import '../discover/discover_controller.dart' show domainDisplayLabel, isTopIntellectTierProvider;
import '../discover/discover_promote_dialog.dart';
import '../discover/truth_judgment_section.dart';
import 'comments_sheet.dart';
import 'compose_sheet.dart';
import 'feed_controller.dart';
import 'fullscreen_media_viewer.dart';
import 'intellect_badge.dart';
import 'media_carousel.dart';
import 'native_ad_tile.dart';
import 'post.dart';
import 'quoted_post_card.dart';
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
    final hasCompletedDailyToday =
        ref.watch(hasCompletedDailyTodayProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.feedAppBarTitle),
        // design/product.md 4章: Discover/BattleはボトムナビゲーションのタブになったためAppBarから撤去。
        actions: [
          if (currentUser != null) ...[
            IconButton(
              tooltip: '投稿',
              // design/system.md「設定・編集系UIの方針」: Composeはボトムシートとして開く
              // （ProfileEditSheetと同じ`showModalBottomSheet`パターン）。
              onPressed: () => showComposeSheet(context),
              icon: const Icon(Icons.add_box_outlined),
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
              tooltip: hasCompletedDailyToday
                  ? l10n.feedDailyQuizCompletedTooltip
                  : l10n.feedDailyQuizTooltip,
              onPressed: hasCompletedDailyToday
                  ? null
                  : () => context.push('/daily-quiz'),
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
                ButtonSegment(
                  value: LayerFilter.all,
                  label: Text(l10n.feedFilterAll),
                ),
                ButtonSegment(
                  value: LayerFilter.top25,
                  label: Text(l10n.feedFilterTop25),
                ),
                ButtonSegment(
                  value: LayerFilter.top5,
                  label: Text(l10n.feedFilterTop5),
                ),
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
                    // 画面外の写真・動画は画面サイズの2倍のスクロール領域に入って
                    // 初めてプリロードされるようにする（onstage/offstageのビルドを前倒しし、
                    // CachedNetworkImage/VideoPlayerControllerの初期化がこのタイミングで走る）。
                    cacheExtent: MediaQuery.of(context).size.height * 2,
                    itemCount: itemCount,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final isAdSlot = (index + 1) % blockSize == 0;
                      if (isAdSlot) {
                        return const NativeAdTile();
                      }
                      final postIndex = index - (index ~/ blockSize);
                      return PostTile(post: posts[postIndex]);
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
      // design/product.md 4章: 投稿作成はAppBarの投稿ボタンからComposeSheetを開く方式に
      // 統一したため、Feed画面独自のFABは撤去する。
    );
  }
}

/// design/product.md 3.15節「デイリーミッションの受験可否・クールダウン表示」。
/// UTC0時までの残り時間を`HH:mm`形式で1分ごとに更新表示する。
class _DailyQuizCooldownLabel extends StatefulWidget {
  const _DailyQuizCooldownLabel();

  @override
  State<_DailyQuizCooldownLabel> createState() =>
      _DailyQuizCooldownLabelState();
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
    final nextResetUtc = DateTime.utc(
      nowUtc.year,
      nowUtc.month,
      nowUtc.day,
    ).add(const Duration(days: 1));
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
            subtitle: Text(
              AppLocalizations.of(context).feedOnboardingBannerSubtitle,
            ),
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
/// Instagram/X風、ラベルなしのアイコンのみ。件数は1以上の場合のみアイコン右側に表示する。
class _ActionBarButton extends StatelessWidget {
  const _ActionBarButton({
    required this.icon,
    required this.onPressed,
    this.count,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: effectiveColor),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$count',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: effectiveColor),
            ),
          ],
        ],
      ),
    );
  }
}

/// 投稿1件のカード表示。フィード一覧・投稿詳細画面（[PostDetailPage]）の両方から使う。
///
/// [showAbsoluteTime] が`true`の場合は絶対時刻（詳細画面向け）、`false`の場合は
/// 相対時刻（一覧画面向け）で作成日時を表示する。[enableThreadNavigation] が`true`の場合、
/// 本文タップで投稿詳細画面へ遷移する（一覧画面用。詳細画面自身では`false`にして無効化する）。
class PostTile extends ConsumerStatefulWidget {
  const PostTile({
    super.key,
    required this.post,
    this.showAbsoluteTime = false,
    this.enableThreadNavigation = true,
  });

  final Post post;
  final bool showAbsoluteTime;
  final bool enableThreadNavigation;

  @override
  ConsumerState<PostTile> createState() => _PostTileState();
}

class _PostTileState extends ConsumerState<PostTile> {
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
      await ref
          .read(feedControllerProvider)
          .toggleLike(postId: post.id, currentlyLiked: currentlyLiked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.feedLikeError('$e'))));
    }
  }

  /// design/product.md 3.12節「リポスト」。
  Future<void> _handleToggleRepost(bool currentlyReposted) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref
          .read(feedControllerProvider)
          .toggleRepost(postId: post.id, currentlyReposted: currentlyReposted);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.feedRepostError('$e'))));
    }
  }

  /// design/product.md 3.12節「リポスト（X風の2択ボトムシート）」。
  /// リポストアイコンタップ時に「（取り消し付き）リポスト」「引用リポスト」の
  /// 2択を提示する。「リポスト」選択時は既存の[_handleToggleRepost]をそのまま呼ぶため、
  /// 単純リポストのトグル挙動自体は変更しない。
  ///
  /// design/product.md 3.5節「Feed → Discoverのキュレーション」。Create権限
  /// （上位25%以上）保持者かつFeedコンテキストの投稿の場合は、同シートに
  /// 「Discoverへ引き上げる」選択肢も追加する（旧・3 dotsメニューから移設）。
  void _openRepostOptions(bool currentlyReposted) {
    final l10n = AppLocalizations.of(context);
    final canPromoteToDiscover =
        post.context == 'feed' && (ref.read(isTopIntellectTierProvider).value ?? false);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.repeat,
                  color: currentlyReposted ? Colors.green : null,
                ),
                title: Text(
                  currentlyReposted
                      ? l10n.feedRepostSheetUndoRepostOption
                      : l10n.feedRepostSheetRepostOption,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handleToggleRepost(currentlyReposted);
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_quote_outlined),
                title: Text(l10n.feedRepostSheetQuoteOption),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showComposeSheet(context, quotedPost: post);
                },
              ),
              if (canPromoteToDiscover)
                ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: const Text('Discoverへ引き上げる'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showPromoteToDiscoverDialog(context, ref, post.id);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// design/product.md 3.12節「コメント」。ボトムシートでコメント一覧・投稿フォームを表示する。
  void _handleOpenComments() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => CommentsBottomSheet(postId: post.id),
    );
  }

  /// design/product.md 3.13節「タップで全画面表示」。共通の全画面メディアビューアを開く。
  void _openFullscreenImage(List<String> imageUrls, int index) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenMediaViewer(
          imageUrls: imageUrls,
          initialImageIndex: index,
        ),
      ),
    );
  }

  void _openFullscreenVideo(String playbackId) {
    Navigator.of(context, rootNavigator: true).push(
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
    final imageUrls =
        post.mediaType == 'image' && (post.mediaUrls?.isNotEmpty ?? false)
        ? post.mediaUrls!
        : null;
    final l10n = AppLocalizations.of(context);

    final authorName = post.authorUsername ?? l10n.feedUnknownUser;
    final firstLetter = authorName.isNotEmpty
        ? authorName[0].toUpperCase()
        : '?';

    final likedIds =
        ref.watch(myLikedPostIdsProvider).value ?? const <String>{};
    final repostedIds =
        ref.watch(myRepostedPostIdsProvider).value ?? const <String>{};
    final isLiked = likedIds.contains(post.id);
    final isReposted = repostedIds.contains(post.id);

    // design/product.md 3.12節「フィード投稿カードのタップ範囲」。カード全体を
    // InkWell/GestureDetectorでラップし、本文以外の余白部分をタップしても投稿詳細へ
    // 遷移できるようにする。メディア・ユーザー情報（アバター/ユーザー名）・アクションバーの
    // 各ボタンは個別に独自のonTapハンドラを持つため、Flutter標準の挙動として子の
    // タップハンドラが優先され、親のカードタップと二重発火しない。
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.enableThreadNavigation
            ? () => context.push('/posts/${post.id}')
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Avatar + Username + Created At
              // design/product.md 3.12節「ユーザー情報表示部のタップ範囲」。
              // アバター・ユーザー名・バッジを含む一帯を単一のGestureDetectorでラップし、
              // どこを押してもプロフィールへ遷移するようにする。IntellectBadge自体は
              // `enableTapDetail: false`でバッジ詳細シートを無効化し、このタップを奪わない。
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.push('/profile/${post.authorId}'),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withAlpha((0.3 * 255).toInt()),
                            child: Text(
                              firstLetter,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
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
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // Metadata row: Badge + Staked TP (if applicable)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    IntellectBadge(
                                      percentile: post.authorIntellectPercentile,
                                      enableTapDetail: false,
                                    ),
                                    if (post.postType == 'staked')
                                      Chip(
                                        avatar: const Icon(Icons.bolt, size: 14),
                                        label: Text(
                                          l10n.feedStakedTpLabel(post.stakedTp as int),
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.tertiaryContainer,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.showAbsoluteTime
                        ? absoluteTimeLabel(post.createdAt)
                        : relativeTimeLabel(l10n, post.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Post body text（カード全体のInkWellが投稿詳細への遷移を担うため、
              // 本文テキスト自体には個別のタップハンドラを持たせない）
              if (post.body.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    post.body,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              // design/system.md 6.1節「ドメインラベリング」。AIが自動付与した産業分類タグ。
              if (post.domainLabels != null &&
                  post.domainLabels!.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: post.domainLabels!.map((label) {
                    return Chip(
                      avatar: const Icon(Icons.auto_awesome, size: 14),
                      label: Text(
                        domainDisplayLabel(label),
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
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
                            onFullscreenTap: () =>
                                _openFullscreenVideo(post.videoPlaybackId!),
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
              // design/product.md 3.12節「引用リポスト」。引用元投稿の要約ミニカード。
              // タップで引用元投稿の詳細画面へ遷移する（一覧タップと同じ`/posts/:postId`遷移）。
              if (post.quotedPost != null) ...[
                QuotedPostCard(
                  quotedPost: post.quotedPost!,
                  onTap: () => openQuotedPostDetail(context, post.quotedPost!.id),
                ),
                const SizedBox(height: 12),
              ],
              // Action bar: Like, Comment, Repost, Share（アイコンのみ。件数は1以上のみ表示）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ActionBarButton(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    count: post.likeCount,
                    color: isLiked ? Colors.red : null,
                    onPressed: () => _handleToggleLike(isLiked),
                  ),
                  _ActionBarButton(
                    icon: Icons.chat_bubble_outline,
                    count: post.commentCount,
                    onPressed: _handleOpenComments,
                  ),
                  _ActionBarButton(
                    icon: Icons.repeat,
                    count: post.repostCount,
                    color: isReposted ? Colors.green : null,
                    onPressed: () => _openRepostOptions(isReposted),
                  ),
                  _ActionBarButton(
                    icon: Icons.share_outlined,
                    onPressed: _handleShare,
                  ),
                ],
              ),
              // design/product.md 3.4節「真偽投票」。Feed/Discover双方の投稿に表示する
              // （旧: Discover画面側で個別に表示していたが、PostTile側へ統合した）。
              TruthJudgmentSection(postId: post.id, postAuthorId: post.authorId),
            ],
          ),
        ),
      ),
    );
  }
}
