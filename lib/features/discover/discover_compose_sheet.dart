import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'discover_controller.dart';

/// design/product.md 2.1節「Discoverの`Create`権限」・3.4節「ステーキング・ツイート」。
/// Create権限（上位25%以上）保持者のみが呼び出せる、Discoverへの新規投稿ボトムシート。
/// `create_discover_post` RPCは通常投稿より高いTP消費を課すため、`ComposeSheet`
/// （Feed用）とは分けたシンプルな専用UIとする。
class DiscoverComposeSheet extends ConsumerStatefulWidget {
  const DiscoverComposeSheet({super.key});

  @override
  ConsumerState<DiscoverComposeSheet> createState() => _DiscoverComposeSheetState();
}

class _DiscoverComposeSheetState extends ConsumerState<DiscoverComposeSheet> {
  final _bodyController = TextEditingController();
  final _stakeController = TextEditingController(text: '20');
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _bodyController.dispose();
    _stakeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _bodyController.text.trim();
    final stake = num.tryParse(_stakeController.text.trim());
    if (body.isEmpty) {
      setState(() => _errorMessage = '投稿内容を入力してください');
      return;
    }
    if (stake == null || stake <= 0) {
      setState(() => _errorMessage = '賭けるTPは1以上を指定してください');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(discoverControllerProvider).createDiscoverPost(body: body, stakedTp: stake);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = '$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Text(
                      'Discoverへ投稿',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('投稿'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bodyController,
                  minLines: 4,
                  maxLines: 10,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    hintText: '知的な考察を投稿する',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stakeController,
                  enabled: !_isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  decoration: const InputDecoration(
                    labelText: '賭けるTP',
                    helperText: 'Discover新規投稿は通常投稿より高いTP消費が課されます',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [DiscoverComposeSheet]をモーダルボトムシートとして開く共通処理。
Future<void> showDiscoverComposeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const DiscoverComposeSheet(),
  );
}
