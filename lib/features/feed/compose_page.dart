import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth_state.dart';
import 'feed_controller.dart';

/// design/system.md のテキスト投稿・画像投稿作成画面。
///
/// ログイン中のユーザーのみ投稿できる。未ログイン時は投稿ボタンを無効化し、
/// ログインを促す案内を表示する。
class ComposePage extends ConsumerStatefulWidget {
  const ComposePage({super.key});

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _selectedImage = picked;
      _selectedImageBytes = bytes;
    });
  }

  void _clearImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  Future<void> _submit() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      setState(() => _errorMessage = 'ログインしてから投稿してください');
      return;
    }
    final hasImage = _selectedImage != null && _selectedImageBytes != null;
    if (_controller.text.trim().isEmpty && !hasImage) {
      setState(() => _errorMessage = '投稿内容を入力するか、画像を選択してください');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final controller = ref.read(feedControllerProvider);
      if (hasImage) {
        final fileExt = (_selectedImage!.name.contains('.'))
            ? _selectedImage!.name.split('.').last
            : 'jpg';
        final imageUrl = await controller.uploadPostImage(
          userId: currentUser.id,
          bytes: _selectedImageBytes!,
          fileExt: fileExt,
        );
        await controller.createImagePost(
          authorId: currentUser.id,
          body: _controller.text,
          imageUrl: imageUrl,
        );
      } else {
        await controller.createTextPost(authorId: currentUser.id, body: _controller.text);
      }

      if (!mounted) return;
      // 一覧が最新化された状態でフィードへ戻る。
      await ref.read(feedPostsProvider.future);
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '投稿に失敗しました: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final isLoggedIn = currentUser != null;

    return Scaffold(
      appBar: AppBar(title: const Text('投稿を作成')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isLoggedIn)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'ログインすると投稿できます',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 10,
              enabled: isLoggedIn && !_isSubmitting,
              decoration: const InputDecoration(
                hintText: 'いまどうしてる？',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedImageBytes != null)
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _selectedImageBytes!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton(
                    onPressed: _isSubmitting ? null : _clearImage,
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(backgroundColor: Colors.black45),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: isLoggedIn && !_isSubmitting ? _pickImage : null,
                icon: const Icon(Icons.image_outlined),
                label: const Text('画像を選択'),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: isLoggedIn && !_isSubmitting ? _submit : null,
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
      ),
    );
  }
}
