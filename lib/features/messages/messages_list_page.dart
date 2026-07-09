import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import 'dm_conversation.dart';
import 'messages_controller.dart';

/// design/system.md 15章「ダイレクトメッセージ（DM）」。DM会話一覧画面。
class MessagesListPage extends ConsumerWidget {
  const MessagesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final conversationsAsync = ref.watch(conversationListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.messagesListAppBarTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(conversationListProvider);
          await ref.read(conversationListProvider.future);
        },
        child: conversationsAsync.when(
          data: (conversations) {
            if (conversations.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(l10n.messagesListEmpty)),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) => _ConversationTile(conversation: conversations[index]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text(l10n.messagesListLoadError('$error'))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final DmConversationSummary conversation;

  void _openMenu(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.block),
                title: Text(l10n.messagesListBlockAction),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await ref.read(messagesControllerProvider).blockUser(conversation.otherUserId);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.messagesListDeleteAction),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await ref
                        .read(messagesControllerProvider)
                        .deleteConversation(conversation.id);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = conversation.otherUsername ?? l10n.messagesListUnknownUser;
    final avatarUrl = conversation.otherAvatarUrl;
    final unread = conversation.unreadCount > 0;

    return Dismissible(
      key: ValueKey('dm-conversation-${conversation.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        try {
          await ref.read(messagesControllerProvider).deleteConversation(conversation.id);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
          }
          return false;
        }
        return true;
      },
      child: ListTile(
        leading: GestureDetector(
          onTap: () => context.push('/profile/${conversation.otherUserId}'),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: avatarUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
        ),
        title: Text(
          name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          conversation.lastMessagePreview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: unread ? FontWeight.w700 : FontWeight.normal,
            color: unread ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateFormat.Md().add_Hm().format(conversation.lastMessageAt.toLocal()),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (unread) ...[
              const SizedBox(height: 4),
              CircleAvatar(
                radius: 9,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  '${conversation.unreadCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        onTap: () => context.push('/messages/${conversation.id}'),
        onLongPress: () => _openMenu(context, ref),
      ),
    );
  }
}
