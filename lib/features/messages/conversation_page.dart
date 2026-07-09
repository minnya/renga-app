import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';
import '../../l10n/gen/app_localizations.dart';
import '../feed/fullscreen_media_viewer.dart';
import '../feed/video_player_widget.dart';
import 'dm_message.dart';
import 'messages_controller.dart';

/// design/system.md 15章「ダイレクトメッセージ（DM）」。1対1の会話詳細（チャット）画面。
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final _inputController = TextEditingController();
  bool _sending = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    // design/system.md 15.3節「Realtime」。新着メッセージ/既読更新を購読し、
    // 一覧をinvalidateして再取得させる。
    _channel = supabase
        .channel('dm_messages:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'dm_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) => _onRemoteChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'dm_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) => _onRemoteChange(),
        )
        .subscribe();

    // 画面表示時に自分宛の未読メッセージを既読にする。
    // ignore: discarded_futures
    ref.read(messagesControllerProvider).markAsRead(widget.conversationId);
  }

  void _onRemoteChange() {
    if (!mounted) return;
    ref.invalidate(conversationMessagesProvider(widget.conversationId));
    // ignore: discarded_futures
    ref.read(messagesControllerProvider).markAsRead(widget.conversationId);
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      // ignore: discarded_futures
      supabase.removeChannel(channel);
    }
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _handleSendText() async {
    final body = _inputController.text.trim();
    if (body.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(messagesControllerProvider).sendTextMessage(
            conversationId: widget.conversationId,
            body: body,
          );
      _inputController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.messagesConversationSendError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handlePickAndSendImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileExt = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      await ref.read(messagesControllerProvider).sendImageMessage(
            conversationId: widget.conversationId,
            bytes: bytes,
            fileExt: fileExt,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.messagesConversationSendError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handlePickAndSendVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(messagesControllerProvider).sendVideoMessage(
            conversationId: widget.conversationId,
            video: picked,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.messagesConversationSendError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleBlockToggle(String otherUserId, bool currentlyBlocked) async {
    final l10n = AppLocalizations.of(context);
    if (!currentlyBlocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.messagesConversationBlockConfirmTitle),
          content: Text(l10n.messagesConversationBlockConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.messagesListBlockAction),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      final controller = ref.read(messagesControllerProvider);
      if (currentlyBlocked) {
        await controller.unblockUser(otherUserId);
      } else {
        await controller.blockUser(otherUserId);
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _handleDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.messagesConversationDeleteConfirmTitle),
        content: Text(l10n.messagesConversationDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.messagesListDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(messagesControllerProvider).deleteConversation(widget.conversationId);
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final messagesAsync = ref.watch(conversationMessagesProvider(widget.conversationId));
    final conversationsAsync = ref.watch(conversationListProvider);

    final summary = conversationsAsync.value
        ?.where((c) => c.id == widget.conversationId)
        .cast<dynamic>()
        .firstOrNull;
    final otherUserId = summary?.otherUserId as String?;
    final otherUsername = summary?.otherUsername as String? ?? l10n.messagesListUnknownUser;

    return Scaffold(
      appBar: AppBar(
        title: otherUserId != null
            ? GestureDetector(
                onTap: () => context.push('/profile/$otherUserId'),
                child: Text(otherUsername),
              )
            : Text(otherUsername),
        actions: [
          if (otherUserId != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'block') {
                  await _handleBlockToggle(otherUserId, false);
                } else if (value == 'unblock') {
                  await _handleBlockToggle(otherUserId, true);
                } else if (value == 'delete') {
                  await _handleDelete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'block', child: Text(l10n.messagesListBlockAction)),
                PopupMenuItem(value: 'unblock', child: Text(l10n.messagesListUnblockAction)),
                PopupMenuItem(value: 'delete', child: Text(l10n.messagesListDeleteAction)),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const SizedBox.shrink();
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final isMe = message.senderId == currentUser?.id;
                    return _MessageBubble(message: message, isMe: isMe);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(child: Text('$error')),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending ? null : _handlePickAndSendImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _handlePickAndSendVideo,
                    icon: const Icon(Icons.videocam_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: InputDecoration(
                        hintText: l10n.messagesConversationInputHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSendText(),
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
                          onPressed: _handleSendText,
                          icon: const Icon(Icons.send),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe});

  final DmMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMe
        ? RengaColors.accent
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMe ? Colors.white : theme.colorScheme.onSurface;

    Widget content;
    if (message.isImage && message.mediaUrl != null) {
      content = GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FullscreenMediaViewer(imageUrls: [message.mediaUrl!]),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: message.mediaUrl!,
            width: 200,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (message.isVideo && message.muxPlaybackId != null) {
      content = GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FullscreenMediaViewer(videoPlaybackId: message.muxPlaybackId!),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 240,
            child: MuxVideoPlayerWidget(playbackId: message.muxPlaybackId!, isPreview: true),
          ),
        ),
      );
    } else if (message.isVideo) {
      // アップロード直後・トランスコード処理中（design/system.md 5.1節のpending/uploading/processing）。
      content = Container(
        width: 200,
        height: 120,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 8),
            Text('動画を処理中…', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    } else {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(message.body ?? '', style: TextStyle(color: textColor)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 2),
                Text(
                  DateFormat.Hm().format(message.createdAt.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
