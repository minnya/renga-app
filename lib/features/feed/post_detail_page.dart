import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/time_format.dart';
import 'comment.dart';
import 'feed_controller.dart';
import 'feed_page.dart';
import 'fullscreen_media_viewer.dart';

/// design/product.md 3.12節「投稿詳細（スレッド表示）」。
/// X(Twitter)同様、投稿を親としてその下にコメント（返信）一覧を表示する画面。
/// Discover画面の投稿タイルからもここへ遷移する。
class PostDetailPage extends ConsumerWidget {
  const PostDetailPage({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final postAsync = ref.watch(postByIdProvider(postId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.feedCommentsSheetTitle)),
      body: postAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('$error')),
        data: (post) {
          return ListView(
            children: [
              PostTile(post: post, showAbsoluteTime: true, enableThreadNavigation: false),
              const Divider(height: 1),
              _CommentsSection(postId: postId),
            ],
          );
        },
      ),
    );
  }
}

class _CommentsSection extends ConsumerStatefulWidget {
  const _CommentsSection({required this.postId});

  final String postId;

  @override
  ConsumerState<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<_CommentsSection> {
  final _inputController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final l10n = AppLocalizations.of(context);
    final body = _inputController.text.trim();
    if (body.isEmpty) return;

    setState(() => _sending = true);
    try {
      await ref.read(feedControllerProvider).addComment(postId: widget.postId, body: body);
      _inputController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.feedCommentPostError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final commentsAsync = ref.watch(commentsProvider(widget.postId));
    final currentUser = ref.watch(currentUserProvider);

    return Column(
      children: [
        commentsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text('$error')),
          ),
          data: (comments) {
            if (comments.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(l10n.feedCommentEmpty)),
              );
            }
            return Column(
              children: comments
                  .map((comment) => _CommentRow(comment: comment))
                  .toList(),
            );
          },
        ),
        if (currentUser != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    decoration: InputDecoration(
                      hintText: l10n.feedCommentInputHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
                const SizedBox(width: 8),
                _sending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: _handleSend,
                        icon: const Icon(Icons.send),
                        tooltip: l10n.feedCommentSendButton,
                      ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 詳細画面用のコメント行。一覧（ボトムシート）と異なり作成日時を絶対時刻で表示する。
class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final Comment comment;

  Widget _buildAvatar(BuildContext context) {
    final theme = Theme.of(context);
    final name = comment.authorUsername ?? '';
    final avatarUrl = comment.authorAvatarUrl;

    Widget initialAvatar() {
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      return CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          initial,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    if (avatarUrl == null || avatarUrl.isEmpty) return initialAvatar();
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => initialAvatar(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(left: comment.isReply ? 40 : 16, right: 16, top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/profile/${comment.authorId}'),
            child: _buildAvatar(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/profile/${comment.authorId}'),
                      child: Text(
                        comment.authorUsername ?? l10n.feedUnknownUser,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      absoluteTimeLabel(comment.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (comment.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(comment.body, style: theme.textTheme.bodyMedium),
                ],
                if (comment.mediaUrls != null && comment.mediaUrls!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: comment.mediaUrls!.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final urls = comment.mediaUrls!;
                        return GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  FullscreenMediaViewer(imageUrls: urls, initialImageIndex: index),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: urls[index],
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
