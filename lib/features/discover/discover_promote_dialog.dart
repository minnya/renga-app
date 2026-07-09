import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'discover_controller.dart';

/// design/product.md 3.5節「Feed → Discoverのキュレーション（リポスト）権限」。
/// Create権限（上位25%以上）保持者が、Feed投稿をDiscoverへ引き上げる際にTP消費量を
/// 入力させるダイアログ。`lib/features/feed/feed_page.dart`の投稿カードから呼び出す。
Future<void> showPromoteToDiscoverDialog(BuildContext context, WidgetRef ref, String postId) async {
  final controller = TextEditingController(text: '20');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Discoverへ引き上げる'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('この投稿をDiscoverへ引き上げます。TPを消費します。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: const InputDecoration(
                labelText: '消費するTP',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('引き上げる'),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return;

  final tpCost = num.tryParse(controller.text.trim());
  if (tpCost == null || tpCost <= 0) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('TP消費量は1以上を指定してください')));
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(discoverControllerProvider)
        .promotePostToDiscover(postId: postId, tpCost: tpCost);
    messenger.showSnackBar(const SnackBar(content: Text('Discoverへ引き上げました')));
  } on PostgrestException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
