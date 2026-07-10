import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../quiz/lock_quiz_page.dart';
import 'feed_controller.dart';
import 'post.dart';
import 'quoted_post_card.dart';
import 'video_upload_controller.dart';
import 'youtube_utils.dart';

/// design/product.md 3.4節「TP消費投稿とロジックチェック」の投稿種別。
/// フィードのレイヤーフィルターと同様、feed_page.dartのSegmentedButtonパターンを踏襲する。
enum _ComposeMode { normal, staked }

/// design/product.md 4章「情報アーキテクチャ」/ design/system.md「設定・編集系UIの方針」。
/// テキスト投稿・画像投稿・動画投稿の作成を行うモーダルボトムシート。
///
/// `lib/features/profile/profile_edit_sheet.dart`の`ProfileEditSheet`と同じ
/// `showModalBottomSheet`パターンで、専用の別画面（旧`ComposePage`）は持たない。
///
/// ログイン中のユーザーのみ投稿できる。未ログイン時は投稿ボタンを無効化し、
/// ログインを促す案内を表示する。
/// design/product.md 3.4節に従い、通常投稿とTP消費投稿を切り替えられる。
/// TP消費投稿はロック解除クイズ（design/product.md 3.2節）に全問正解しないと送信できない。
class ComposeSheet extends ConsumerStatefulWidget {
  /// design/product.md 3.1節「YouTubeアプリの共有シートに登場」。
  /// YouTubeアプリの共有シート等からRengaが起動された場合、共有された
  /// テキスト（動画タイトル+URL）を本文へ自動プリフィルするための初期値。
  ///
  /// [quotedPost]を指定すると design/product.md 3.12節「引用リポスト」モードで開く。
  /// この場合、投稿本文の上に引用元投稿のミニカードを表示し、送信時は
  /// `posts.quoted_post_id`に引用元投稿のIDをセットして投稿する
  /// （通常投稿・画像投稿・動画投稿いずれのモードでも引用元IDを付与できる）。
  const ComposeSheet({super.key, this.initialBody, this.quotedPost});

  final String? initialBody;
  final Post? quotedPost;

  @override
  ConsumerState<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<ComposeSheet> {
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
    // design/product.md 3.12節「引用リポスト」: 引用元投稿自体が本文の役割を持つため、
    // 引用リポスト時はコメント本文が空でも投稿できる（X同様）。
    if (_controller.text.trim().isEmpty &&
        !hasImage &&
        !hasVideo &&
        widget.quotedPost == null) {
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
          quotedPostId: widget.quotedPost?.id,
        );
      } else if (hasVideo) {
        // design/system.md 5.1節「動画アップロードフロー」。先に posts レコードを作成し、
        // その post_id に紐づけて videos レコード作成＋Mux Direct Uploadを行う。
        final postId = await controller.createVideoPost(
          authorId: currentUser.id,
          body: _controller.text,
          quotedPostId: widget.quotedPost?.id,
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
        await controller.createTextPost(
          authorId: currentUser.id,
          body: _controller.text,
          quotedPostId: widget.quotedPost?.id,
        );
      }

      if (!mounted) return;
      // 一覧が最新化された状態でシートを閉じる。
      await ref.read(feedPostsProvider.future);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = AppLocalizations.of(context).composeSubmitError('$e'));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// design/product.md 3.4節「TP消費投稿」。
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

    // ロック解除クイズに全問正解しないとTP消費投稿はブロックされる。
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
      Navigator.of(context).pop();
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

    return Padding(
      // design/system.md「設定・編集系UIの方針」: ProfileEditSheetと同様、キーボード表示時に
      // シートがキーボードの上に押し上げられるよう、viewInsets.bottom分をパディングする。
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // X(Twitter)風：左キャンセル（閉じる）、右投稿ボタン
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: isLoggedIn && !_isSubmitting ? _submit : null,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(l10n.composeSubmitButton),
                    ),
                  ],
                ),
                if (_isSubmitting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  if (!isLoggedIn)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        l10n.composeLoginPrompt,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  // 本文入力欄：ボーダーなし、大きめテキスト
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextField(
                      controller: _controller,
                      minLines: 4,
                      maxLines: 10,
                      enabled: isLoggedIn && !_isSubmitting,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        hintText: l10n.composeBodyHint,
                        hintStyle: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  // design/product.md 3.12節「引用リポスト」。引用元投稿のミニカードプレビュー
                  // （タップ不可。送信先を誤認させないため`onTap`は渡さない）。
                  if (widget.quotedPost != null) ...[
                    Text(
                      l10n.composeQuotedPostSectionLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    QuotedPostCard(
                      quotedPost: QuotedPostPreview.fromPost(widget.quotedPost!),
                    ),
                  ],
                  // メディア表示（通常投稿のみ）
                  if (_mode == _ComposeMode.normal) ...[
                    if (_selectedImageBytes != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                _selectedImageBytes!,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            IconButton(
                              onPressed: _isSubmitting ? null : _clearImage,
                              icon: const Icon(Icons.close, color: Colors.white),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_selectedVideo != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Container(
                              height: 140,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.videocam,
                                      size: 40,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _selectedVideo!.name,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (_videoUploadProgress != null) ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: 160,
                                        child: LinearProgressIndicator(
                                          value: _videoUploadProgress,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _isSubmitting ? null : _clearVideo,
                              icon: const Icon(Icons.close, color: Colors.white),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // YouTube プレビュー
                    if (_youtubeController != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: YoutubePlayer(controller: _youtubeController!),
                        ),
                      ),
                  ],
                  // エラーメッセージ
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  // TP消費投稿の場合、TP入力フィールド
                  if (_mode == _ComposeMode.staked)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        controller: _stakedTpController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        enabled: isLoggedIn && !_isSubmitting,
                        decoration: InputDecoration(
                          labelText: l10n.composeStakedTpLabel,
                          helperText: l10n.composeStakedTpHelper,
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                      ),
                    ),
                  // 下部ツールバー：X(Twitter)投稿画面風のアイコン行
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 16),
                    child: Divider(
                      color: Theme.of(context).colorScheme.outline,
                      height: 1,
                    ),
                  ),
                  // 投稿モード切替（SegmentedButton）。design/product.md 3.12節「引用リポスト」:
                  // TP消費投稿（`create_staked_post` RPC）は引用元IDを扱えないため、
                  // 引用リポストモードでは非表示にし常に通常投稿として扱う。
                  if (widget.quotedPost == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SegmentedButton<_ComposeMode>(
                        segments: [
                          ButtonSegment(
                            value: _ComposeMode.normal,
                            label: Text(l10n.composeNormalModeLabel),
                          ),
                          ButtonSegment(
                            value: _ComposeMode.staked,
                            label: Text(l10n.composeStakedModeLabel),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (isLoggedIn && !_isSubmitting)
                            ? (selection) => setState(() => _mode = selection.first)
                            : null,
                      ),
                    ),
                  // ツールバーアイコン行：画像・動画選択（通常投稿のみ）
                  if (_mode == _ComposeMode.normal && _selectedImageBytes == null && _selectedVideo == null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.image_outlined),
                          onPressed: isLoggedIn && !_isSubmitting ? _pickImage : null,
                          tooltip: l10n.composePickImageButton,
                        ),
                        IconButton(
                          icon: const Icon(Icons.videocam_outlined),
                          onPressed: isLoggedIn && !_isSubmitting ? _pickVideo : null,
                          tooltip: l10n.composePickVideoButton,
                        ),
                      ],
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

/// design/product.md 3.1節「YouTubeアプリの共有シートに登場」。
/// 共有された動画リンクをプリフィルした状態で[ComposeSheet]をボトムシートとして開く共通処理。
/// Feed画面の投稿ボタン（`lib/features/feed/feed_page.dart`）と共有シート受信導線
/// （`lib/main.dart`、`/compose`ディープリンク経由）の両方から呼び出す。
Future<void> showComposeSheet(
  BuildContext context, {
  String? initialBody,
  Post? quotedPost,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ComposeSheet(initialBody: initialBody, quotedPost: quotedPost),
  );
}

/// design/system.md「設定・編集系UIの方針」。`/compose`ディープリンク（`lib/main.dart`の
/// 共有シート受信導線がBuildContextを直接持てないためgo_router経由でここへ遷移する）専用の
/// 薄いルートページ。遷移直後に[ComposeSheet]をボトムシートとして開き、シートが閉じたら
/// このルート自体もpopして元の画面へ戻す。
class ComposeRoutePage extends StatefulWidget {
  const ComposeRoutePage({super.key, this.initialBody});

  final String? initialBody;

  @override
  State<ComposeRoutePage> createState() => _ComposeRoutePageState();
}

class _ComposeRoutePageState extends State<ComposeRoutePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showComposeSheet(context, initialBody: widget.initialBody);
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Colors.transparent, body: SizedBox.shrink());
  }
}
