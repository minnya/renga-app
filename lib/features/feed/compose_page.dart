import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../quiz/lock_quiz_page.dart';
import 'feed_controller.dart';
import 'video_upload_controller.dart';
import 'youtube_utils.dart';

/// design/product.md 3.4節「ステーキングとロジックチェック」の投稿種別。
/// フィードのレイヤーフィルターと同様、feed_page.dartのSegmentedButtonパターンを踏襲する。
enum _ComposeMode { normal, staked }

/// design/system.md のテキスト投稿・画像投稿・動画投稿作成画面。
///
/// ログイン中のユーザーのみ投稿できる。未ログイン時は投稿ボタンを無効化し、
/// ログインを促す案内を表示する。
/// design/product.md 3.4節に従い、通常投稿とステーキング投稿を切り替えられる。
/// ステーキング投稿はロック解除クイズ（design/product.md 3.2節）に全問正解しないと送信できない。
class ComposePage extends ConsumerStatefulWidget {
  /// design/product.md 3.1節「YouTubeアプリの共有シートに登場」。
  /// YouTubeアプリの共有シート等からRengaが起動された場合、共有された
  /// テキスト（動画タイトル+URL）を本文へ自動プリフィルするための初期値。
  const ComposePage({super.key, this.initialBody});

  final String? initialBody;

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  final _controller = TextEditingController();
  final _stakedTpController = TextEditingController(text: '10');
  bool _isSubmitting = false;
  String? _errorMessage;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  XFile? _selectedVideo;
  double? _videoUploadProgress;
  YoutubePlayerController? _youtubeController;
  String? _previewedYoutubeVideoId;
  _ComposeMode _mode = _ComposeMode.normal;

  @override
  void initState() {
    super.initState();
    if (widget.initialBody != null && widget.initialBody!.isNotEmpty) {
      _controller.text = widget.initialBody!;
    }
    _controller.addListener(_onBodyChanged);
    // 初期値がある場合（共有シート起点の起動）もプレビューを反映させる。
    _onBodyChanged();
  }

  @override
  void dispose() {
    _controller.removeListener(_onBodyChanged);
    _controller.dispose();
    _stakedTpController.dispose();
    _youtubeController?.dispose();
    super.dispose();
  }

  /// design/system.md 5.3節。本文にYouTube URLが含まれる場合、自動でプレビューカードを出す。
  void _onBodyChanged() {
    final videoId = extractYoutubeVideoId(_controller.text);
    if (videoId == _previewedYoutubeVideoId) return;
    setState(() {
      _previewedYoutubeVideoId = videoId;
      _youtubeController?.dispose();
      _youtubeController = videoId == null
          ? null
          : YoutubePlayerController(
              initialVideoId: videoId,
              flags: const YoutubePlayerFlags(autoPlay: false, mute: false),
            );
    });
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _selectedImage = picked;
      _selectedImageBytes = bytes;
      _selectedVideo = null;
    });
  }

  void _clearImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  Future<void> _pickVideo() async {
    final picked = await VideoUploadController().pickVideo();
    if (picked == null) return;
    setState(() {
      _selectedVideo = picked;
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  void _clearVideo() {
    setState(() {
      _selectedVideo = null;
      _videoUploadProgress = null;
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      setState(() => _errorMessage = l10n.composeLoginRequiredError);
      return;
    }

    if (_mode == _ComposeMode.staked) {
      await _submitStaked();
      return;
    }

    final hasImage = _selectedImage != null && _selectedImageBytes != null;
    final hasVideo = _selectedVideo != null;
    if (_controller.text.trim().isEmpty && !hasImage && !hasVideo) {
      setState(() => _errorMessage = l10n.composeEmptyError);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      if (hasVideo) _videoUploadProgress = 0;
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
      } else if (hasVideo) {
        // design/system.md 5.1節「動画アップロードフロー」。先に posts レコードを作成し、
        // その post_id に紐づけて videos レコード作成＋Mux Direct Uploadを行う。
        final postId = await controller.createVideoPost(
          authorId: currentUser.id,
          body: _controller.text,
        );
        await VideoUploadController().uploadVideo(
          video: _selectedVideo!,
          postId: postId,
          uploaderId: currentUser.id,
          onProgress: (progress) {
            if (mounted) setState(() => _videoUploadProgress = progress);
          },
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
      setState(() => _errorMessage = AppLocalizations.of(context).composeSubmitError('$e'));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// design/product.md 3.4節「ステーキング・ツイート」。
  /// design/product.md 3.2節「ロック解除クイズ（通行料）」を投稿前に必須で挟み、
  /// 全問正解した場合のみ `create_staked_post` RPC（design/system.md 7章参照）で
  /// TP減算と投稿作成をアトミックに行う。
  Future<void> _submitStaked() async {
    final l10n = AppLocalizations.of(context);
    if (_controller.text.trim().isEmpty) {
      setState(() => _errorMessage = l10n.composeStakedEmptyError);
      return;
    }
    final stakedTp = num.tryParse(_stakedTpController.text.trim());
    if (stakedTp == null || stakedTp <= 0) {
      setState(() => _errorMessage = l10n.composeStakedInvalidTpError);
      return;
    }

    setState(() => _errorMessage = null);

    // ロック解除クイズに全問正解しないとステーキング投稿はブロックされる。
    final passed = await showLockQuizDialog(context);
    if (!mounted) return;
    if (!passed) {
      setState(() => _errorMessage = l10n.composeStakedLockFailedError);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final controller = ref.read(feedControllerProvider);
      await controller.createStakedPost(body: _controller.text, stakedTp: stakedTp);

      if (!mounted) return;
      await ref.read(feedPostsProvider.future);
      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = AppLocalizations.of(context).composeStakedSubmitError('$e'));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.watch(currentUserProvider);
    final isLoggedIn = currentUser != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.composeAppBarTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isLoggedIn)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l10n.composeLoginPrompt,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            // design/product.md 3.4節「通常投稿 / ステーキング投稿」の切替UI。
            // feed_page.dartのレイヤーフィルターと同じSegmentedButtonパターンに倣う。
            SegmentedButton<_ComposeMode>(
              segments: [
                ButtonSegment(value: _ComposeMode.normal, label: Text(l10n.composeNormalModeLabel)),
                ButtonSegment(value: _ComposeMode.staked, label: Text(l10n.composeStakedModeLabel)),
              ],
              selected: {_mode},
              onSelectionChanged: (isLoggedIn && !_isSubmitting)
                  ? (selection) => setState(() => _mode = selection.first)
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 10,
              enabled: isLoggedIn && !_isSubmitting,
              decoration: InputDecoration(
                hintText: l10n.composeBodyHint,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_mode == _ComposeMode.staked) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _stakedTpController,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                enabled: isLoggedIn && !_isSubmitting,
                decoration: InputDecoration(
                  labelText: l10n.composeStakedTpLabel,
                  helperText: l10n.composeStakedTpHelper,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_mode == _ComposeMode.normal) ...[
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
              else if (_selectedVideo != null)
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selectedVideo!.name),
                            if (_videoUploadProgress != null) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 160,
                                child: LinearProgressIndicator(value: _videoUploadProgress),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isSubmitting ? null : _clearVideo,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isLoggedIn && !_isSubmitting ? _pickImage : null,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(l10n.composePickImageButton),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isLoggedIn && !_isSubmitting ? _pickVideo : null,
                        icon: const Icon(Icons.videocam_outlined),
                        label: Text(l10n.composePickVideoButton),
                      ),
                    ),
                  ],
                ),
              // design/system.md 5.3節。本文にYouTube URLが含まれる場合の自動プレビュー。
              if (_youtubeController != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: YoutubePlayer(controller: _youtubeController!),
                ),
              ],
            ],
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
                  : Text(l10n.composeSubmitButton),
            ),
          ],
        ),
      ),
    );
  }
}
