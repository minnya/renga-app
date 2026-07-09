import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';
import '../feed/video_upload_controller.dart';
import 'dm_conversation.dart';
import 'dm_message.dart';

/// design/system.md 15章「ダイレクトメッセージ（DM）」。
/// ログインユーザーが参加しているDM会話一覧（自分側で削除済みのものは除く）を
/// 相手プロフィール・最新メッセージ・未読数付きで取得する。
///
/// `dm_conversations`から`user_a_id`/`user_b_id`双方に`profiles(username, avatar_url)`を
/// ネストselectし、Dart側で「自分ではない方」のプロフィールを選ぶ。未読数はN+1になるが
/// [feedPostsProvider]等の既存実装と同様、MVP規模のデータでは許容する。
final conversationListProvider = FutureProvider<List<DmConversationSummary>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final deletionRows = await supabase
      .from('dm_conversation_deletions')
      .select('conversation_id')
      .eq('user_id', user.id);
  final deletedConversationIds = deletionRows.map((row) => row['conversation_id'] as String).toSet();

  final rows = await supabase
      .from('dm_conversations')
      .select(
        'id, user_a_id, user_b_id, last_message_at, '
        'user_a:profiles!dm_conversations_user_a_id_fkey(username, display_name, avatar_url), '
        'user_b:profiles!dm_conversations_user_b_id_fkey(username, display_name, avatar_url)',
      )
      .or('user_a_id.eq.${user.id},user_b_id.eq.${user.id}')
      .order('last_message_at', ascending: false);

  final summaries = <DmConversationSummary>[];
  for (final row in rows) {
    final id = row['id'] as String;
    if (deletedConversationIds.contains(id)) continue;

    final userAId = row['user_a_id'] as String;
    final isUserA = userAId == user.id;
    final otherUserId = isUserA ? row['user_b_id'] as String : userAId;
    final otherProfile = (isUserA ? row['user_b'] : row['user_a']) as Map<String, dynamic>?;

    final lastMessageRow = await supabase
        .from('dm_messages')
        .select('body, media_type')
        .eq('conversation_id', id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final unreadRows = await supabase
        .from('dm_messages')
        .select('id')
        .eq('conversation_id', id)
        .neq('sender_id', user.id)
        .isFilter('read_at', null);

    summaries.add(
      DmConversationSummary(
        id: id,
        otherUserId: otherUserId,
        otherUsername: (otherProfile?['display_name'] as String?)?.trim().isNotEmpty == true
            ? otherProfile!['display_name'] as String
            : otherProfile?['username'] as String?,
        otherAvatarUrl: otherProfile?['avatar_url'] as String?,
        lastMessageAt: DateTime.parse(row['last_message_at'] as String),
        lastMessagePreview: _previewFor(lastMessageRow),
        unreadCount: unreadRows.length,
      ),
    );
  }

  return summaries;
});

String _previewFor(Map<String, dynamic>? row) {
  if (row == null) return '';
  final mediaType = row['media_type'] as String? ?? 'text';
  switch (mediaType) {
    case 'image':
      return '📷 画像';
    case 'video':
      return '🎬 動画';
    default:
      final body = (row['body'] as String?) ?? '';
      return body;
  }
}

/// design/system.md 15章。指定した会話のメッセージ一覧（作成日時昇順）。
final conversationMessagesProvider = FutureProvider.family<List<DmMessage>, String>((
  ref,
  conversationId,
) async {
  final rows = await supabase
      .from('dm_messages')
      .select()
      .eq('conversation_id', conversationId)
      .order('created_at');
  return rows.map((row) => DmMessage.fromMap(row)).toList();
});

/// DM関連の操作をまとめたコントローラー。
class MessagesController {
  MessagesController(this.ref);

  final Ref ref;

  /// design/system.md 15章。相手ユーザーとの会話を取得または新規作成する。
  Future<String> startConversation(String otherUserId) async {
    final result = await supabase.rpc(
      'get_or_create_dm_conversation',
      params: {'p_other_user_id': otherUserId},
    );
    ref.invalidate(conversationListProvider);
    return result as String;
  }

  Future<void> sendTextMessage({required String conversationId, required String body}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

    await supabase.from('dm_messages').insert({
      'conversation_id': conversationId,
      'sender_id': user.id,
      'body': trimmed,
      'media_type': 'text',
    });

    ref.invalidate(conversationMessagesProvider(conversationId));
    ref.invalidate(conversationListProvider);
  }

  /// design/system.md 5章の画像アップロードと同じパターンで`dm-media`バケットへアップロードする。
  Future<String> uploadDmImage({
    required String userId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final uniqueName =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 31)}.$fileExt';
    final path = '$userId/$uniqueName';

    await supabase.storage.from('dm-media').uploadBinary(path, bytes);
    return supabase.storage.from('dm-media').getPublicUrl(path);
  }

  Future<void> sendImageMessage({
    required String conversationId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final imageUrl = await uploadDmImage(userId: user.id, bytes: bytes, fileExt: fileExt);

    await supabase.from('dm_messages').insert({
      'conversation_id': conversationId,
      'sender_id': user.id,
      'media_type': 'image',
      'media_url': imageUrl,
    });

    ref.invalidate(conversationMessagesProvider(conversationId));
    ref.invalidate(conversationListProvider);
  }

  /// design/system.md 5.1節のMux Direct Uploadフローと同じパターンで、DMへ動画を送信する。
  /// 先に`media_type='video'`の`dm_messages`行を作成し、その`id`を`videos.dm_message_id`に
  /// 紐づけてアップロードする。トランスコード完了（`status='ready'`）は
  /// `sync_dm_message_video_ready`トリガーが`dm_messages.mux_playback_id`へ反映する
  /// （`supabase/migrations/20260709120000_sync_dm_message_video_ready.sql`）。
  Future<void> sendVideoMessage({
    required String conversationId,
    required XFile video,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final row = await supabase
        .from('dm_messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': user.id,
          'body': '',
          'media_type': 'video',
        })
        .select('id')
        .single();
    final dmMessageId = row['id'] as String;

    await VideoUploadController().uploadVideo(
      video: video,
      dmMessageId: dmMessageId,
      uploaderId: user.id,
    );

    ref.invalidate(conversationMessagesProvider(conversationId));
    ref.invalidate(conversationListProvider);
  }

  /// 該当会話の自分宛未読メッセージをすべて既読にする。
  Future<void> markAsRead(String conversationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase
        .from('dm_messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .neq('sender_id', user.id)
        .isFilter('read_at', null);

    ref.invalidate(conversationListProvider);
  }

  Future<void> blockUser(String userId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase.from('dm_blocks').insert({'blocker_id': user.id, 'blocked_id': userId});
  }

  Future<void> unblockUser(String userId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase.from('dm_blocks').delete().eq('blocker_id', user.id).eq('blocked_id', userId);
  }

  /// 自分の`dm_blocks`一覧に相手ユーザーが含まれているか。
  Future<bool> isBlockedByMe(String otherUserId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    final row = await supabase
        .from('dm_blocks')
        .select('blocked_id')
        .eq('blocker_id', user.id)
        .eq('blocked_id', otherUserId)
        .maybeSingle();
    return row != null;
  }

  /// design/system.md 15章「自分側のみの論理削除」。
  Future<void> deleteConversation(String conversationId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase.from('dm_conversation_deletions').upsert({
      'conversation_id': conversationId,
      'user_id': user.id,
    });
    ref.invalidate(conversationListProvider);
  }
}

final messagesControllerProvider = Provider<MessagesController>((ref) {
  return MessagesController(ref);
});
