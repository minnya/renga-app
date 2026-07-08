import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import 'comment.dart';
import 'feed_controller.dart';
import 'video_upload_controller.dart';

/// design/product.md 3.12節「基本エンゲージメント機能」のコメント機能。
/// コメント一覧（返信スレッド込み）と投稿フォームを1つのボトムシートにまとめる。
///
/// design/product.md 5章のボトムシート方針に従い、明示的な「キャンセル」ボタンは置かない
/// （スワイプダウン/タップアウトサイドのみが閉じる手段）。
class CommentsBottomSheet extends ConsumerStatefulWidget {
  const CommentsBottomSheet({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<CommentsBottomSheet> createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends ConsumerState<CommentsBottomSheet> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  bool _sending = false;

  /// 返信対象のコメント（トップレベルコメントのみ設定可能。1階層スレッドのため）。
  /// nullの場合は投稿フォームがトップレベルコメントとして送信する。
  Comment? _replyingTo;

  final List<XFile> _selectedImages = [];
  final List<Uint8List> _selectedImageBytes = [];
  XFile? _selectedVideo;

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _startReply(Comment comment) {
    setState(() => _replyingTo = comment);
    _inputFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    final bytesList = await Future.wait(picked.map((f) => f.readAsBytes()));
    setState(() {
      _selectedImages.addAll(picked);
      _selectedImageBytes.addAll(bytesList);
      _selectedVideo = null;
    });
  }

  Future<void> _pickVideo() async {
    final picked = await VideoUploadController().pickVideo();
    if (picked == null) return;
    setState(() {
      _selectedVideo = picked;
      _selectedImages.clear();
      _selectedImageBytes.clear();
    });
  }

  void _removeImageAt(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _selectedImageBytes.removeAt(index);
    });
  }

  void _removeVideo() {
    setState(() => _selectedVideo = null);
  }

  Future<void> _handleSend() async {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final body = _inputController.text.trim();
    final hasImages = _selectedImages.isNotEmpty;
    final hasVideo = _selectedVideo != null;
    if (body.isEmpty && !hasImages && !hasVideo) return;

    setState(() => _sending = true);
    try {
      final controller = ref.read(feedControllerProvider);

      final uploadedImageUrls = <String>[];
      for (var i = 0; i < _selectedImages.length; i++) {
        final name = _selectedImages[i].name;
        final fileExt = name.contains('.') ? name.split('.').last : 'jpg';
        final url = await controller.uploadCommentImage(
          userId: currentUser.id,
          bytes: _selectedImageBytes[i],
          fileExt: fileExt,
        );
        uploadedImageUrls.add(url);
      }

      final commentId = await controller.addComment(
        postId: widget.postId,
        body: body,
        parentCommentId: _replyingTo?.id,
        mediaUrls: uploadedImageUrls.isEmpty ? null : uploadedImageUrls,
      );

      if (hasVideo && commentId != null) {
        await VideoUploadController().uploadVideo(
          video: _selectedVideo!,
          commentId: commentId,
          uploaderId: currentUser.id,
        );
      }

      _inputController.clear();
      setState(() {
        _replyingTo = null;
        _selectedImages.clear();
        _selectedImageBytes.clear();
        _selectedVideo = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.feedCommentPostError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// design/product.md 3.12節「経過時間の相対表示」。1分未満は「たった今」、
  /// 1時間未満は分単位、1日未満は時間単位、7日未満は日単位、それ以降は日付表示にフォールバックする。
  String _relativeTime(AppLocalizations l10n, DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return l10n.feedCommentTimeJustNow;
    if (diff.inHours < 1) return l10n.feedCommentTimeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.feedCommentTimeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.feedCommentTimeDaysAgo(diff.inDays);
    return DateFormat.yMd().format(createdAt);
  }

  Widget _buildAvatar(BuildContext context, Comment comment) {
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

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return initialAvatar();
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: ClipOval(
        child: Image.network(
          avatarUrl,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => initialAvatar(),
        ),
      ),
    );
  }

  Widget _buildAttachments(Comment comment) {
    final urls = comment.mediaUrls;
    if (urls == null || urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (context, index) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                urls[index],
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCommentRow(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    Comment comment, {
    required bool isReply,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: isReply ? 40 : 0, top: isReply ? 8 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(context, comment),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.authorUsername ?? l10n.feedUnknownUser,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeTime(l10n, comment.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (comment.body.isNotEmpty) Text(comment.body, style: theme.textTheme.bodyMedium),
                _buildAttachments(comment),
                if (!isReply)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      onTap: () => _startReply(comment),
                      child: Text(
                        l10n.feedCommentReplyButton,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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

                    final topLevel = comments.where((c) => !c.isReply).toList();
                    final repliesByParent = <String, List<Comment>>{};
                    for (final c in comments.where((c) => c.isReply)) {
                      repliesByParent.putIfAbsent(c.parentCommentId!, () => []).add(c);
                    }

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: topLevel.length,
                      separatorBuilder: (context, index) => const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final comment = topLevel[index];
                        final replies = repliesByParent[comment.id] ?? const <Comment>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildCommentRow(context, l10n, theme, comment, isReply: false),
                            for (final reply in replies)
                              _buildCommentRow(context, l10n, theme, reply, isReply: true),
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
              if (_replyingTo != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.feedCommentReplyingTo(
                            _replyingTo!.authorUsername ?? l10n.feedUnknownUser,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _cancelReply,
                        icon: const Icon(Icons.close, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              if (_selectedImageBytes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImageBytes.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        return Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _selectedImageBytes[index],
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _removeImageAt(index),
                              child: const CircleAvatar(
                                radius: 8,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close, size: 10, color: Colors.white),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              if (_selectedVideo != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.videocam, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _selectedVideo!.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        onPressed: _removeVideo,
                        icon: const Icon(Icons.close, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _sending ? null : _pickImages,
                      icon: const Icon(Icons.image_outlined),
                      tooltip: l10n.feedCommentAttachImageButton,
                    ),
                    IconButton(
                      onPressed: _sending ? null : _pickVideo,
                      icon: const Icon(Icons.videocam_outlined),
                      tooltip: l10n.feedCommentAttachVideoButton,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        decoration: InputDecoration(
                          hintText: _replyingTo != null
                              ? l10n.feedCommentReplyInputHint
                              : l10n.feedCommentInputHint,
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
