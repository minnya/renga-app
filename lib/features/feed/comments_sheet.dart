import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import 'feed_controller.dart';

/// design/product.md 3.12節「基本エンゲージメント機能」のコメント機能。
/// コメント一覧と投稿フォームを1つのボトムシートにまとめる。
class CommentsBottomSheet extends ConsumerStatefulWidget {
  const CommentsBottomSheet({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends ConsumerState<CommentsBottomSheet> {
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
    final theme = Theme.of(context);
    final commentsAsync = ref.watch(commentsProvider(widget.postId));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  l10n.feedCommentsSheetTitle,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: commentsAsync.when(
                  data: (comments) {
                    if (comments.isEmpty) {
                      return Center(child: Text(l10n.feedCommentEmpty));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: comments.length,
                      separatorBuilder: (context, index) => const Divider(height: 16),
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              comment.authorUsername ?? l10n.feedUnknownUser,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(comment.body, style: theme.textTheme.bodyMedium),
                          ],
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => Center(child: Text('$error')),
                ),
              ),
              const Divider(height: 1),
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
          ),
        );
      },
    );
  }
}
