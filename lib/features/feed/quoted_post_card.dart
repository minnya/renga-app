import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import 'post.dart';

/// design/product.md 3.12節「引用リポスト」。X風の引用元投稿ミニカード。
///
/// フィード（[PostTile]・投稿詳細）と投稿作成シート（[ComposeSheet]の引用リポストモード）の
/// 両方から使う共通ウィジェット。
///
/// [onTap]を指定すると（フィード表示時）タップで引用元投稿の詳細画面へ遷移できるようにする。
/// [ComposeSheet]内のプレビューでは`onTap`を渡さず、タップ不可のプレビュー専用表示にする。
class QuotedPostCard extends StatelessWidget {
  const QuotedPostCard({super.key, required this.quotedPost, this.onTap});

  final QuotedPostPreview quotedPost;
  final VoidCallback? onTap;

  static const _kBodyPreviewMaxChars = 140;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final authorName = quotedPost.authorUsername ?? l10n.feedUnknownUser;
    final firstLetter = authorName.isNotEmpty ? authorName[0].toUpperCase() : '?';

    final bodyPreview = quotedPost.body.length > _kBodyPreviewMaxChars
        ? '${quotedPost.body.substring(0, _kBodyPreviewMaxChars)}…'
        : quotedPost.body;

    final thumbnailUrl =
        quotedPost.mediaType == 'image' && (quotedPost.mediaUrls?.isNotEmpty ?? false)
        ? quotedPost.mediaUrls!.first
        : (quotedPost.mediaType == 'video' ? quotedPost.videoThumbnailUrl : null);

    final card = Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: theme.colorScheme.primary.withAlpha((0.3 * 255).toInt()),
                child: Text(
                  firstLetter,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  authorName,
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (bodyPreview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              bodyPreview,
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (thumbnailUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: thumbnailUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// フィード・投稿詳細から引用元投稿の詳細画面へ遷移する際の共通ハンドラ。
/// design/product.md 3.12節「引用元カードのタップ遷移」: 一覧から投稿をタップした時と
/// 同じ`/posts/:postId`遷移を行う。
void openQuotedPostDetail(BuildContext context, String quotedPostId) {
  context.push('/posts/$quotedPostId');
}
