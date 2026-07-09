import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// design/system.md 5.2節「再生・サムネイル」。
///
/// Mux専用SDKへの依存を避け、標準的なHLS再生（`video_player`）で
/// `https://stream.mux.com/{playbackId}.m3u8` を直接再生する。
class MuxVideoPlayerWidget extends StatefulWidget {
  const MuxVideoPlayerWidget({
    super.key,
    required this.playbackId,
    this.autoPlay = false,
    this.isPreview = true,
    this.showFullscreenButton = false,
    this.onFullscreenTap,
  });

  final String playbackId;

  /// trueならスクロールイン等のタイミングでミュート自動再生する。
  final bool autoPlay;

  /// trueはフィード内軽量プレビュー扱い（ミュート・ループ）、
  /// falseは全画面フル品質（ミュート解除・シークバー操作を主体）。
  final bool isPreview;

  final bool showFullscreenButton;
  final VoidCallback? onFullscreenTap;

  @override
  State<MuxVideoPlayerWidget> createState() => _MuxVideoPlayerWidgetState();
}

class _MuxVideoPlayerWidgetState extends State<MuxVideoPlayerWidget> {
  late VideoPlayerController _controller;
  late Future<void> _initializeFuture;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _initializeFuture = _initialize(_controller);
  }

  VideoPlayerController _createController() {
    return VideoPlayerController.networkUrl(
      Uri.parse('https://stream.mux.com/${widget.playbackId}.m3u8'),
    );
  }

  Future<void> _initialize(VideoPlayerController controller) async {
    await controller.initialize();
    if (!mounted || controller != _controller) return;
    if (widget.isPreview) {
      await controller.setLooping(true);
      await controller.setVolume(0);
    } else {
      await controller.setVolume(1);
    }
    if (widget.autoPlay) {
      await controller.play();
    }
  }

  @override
  void didUpdateWidget(covariant MuxVideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playbackId != oldWidget.playbackId) {
      final oldController = _controller;
      final newController = _createController();
      setState(() {
        _controller = newController;
        _initializeFuture = _initialize(newController);
      });
      oldController.dispose();
      return;
    }
    if (widget.autoPlay != oldWidget.autoPlay) {
      if (widget.autoPlay) {
        _controller.play();
      } else {
        _controller.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(child: Text('動画を読み込めませんでした')),
          );
        }
        return AspectRatio(
          aspectRatio: _controller.value.aspectRatio == 0 ? 16 / 9 : _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),
              _PlayPauseOverlay(controller: _controller),
              if (!widget.isPreview)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    padding: EdgeInsets.zero,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
              if (widget.showFullscreenButton)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
                      onPressed: widget.onFullscreenTap,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      splashRadius: 20,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayPauseOverlay extends StatefulWidget {
  const _PlayPauseOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_PlayPauseOverlay> createState() => _PlayPauseOverlayState();
}

class _PlayPauseOverlayState extends State<_PlayPauseOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (widget.controller.value.isPlaying) {
          widget.controller.pause();
        } else {
          widget.controller.play();
        }
      },
      child: AnimatedOpacity(
        opacity: widget.controller.value.isPlaying ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: Colors.black26,
          child: const Icon(Icons.play_arrow, color: Colors.white, size: 56),
        ),
      ),
    );
  }
}

/// `videos.status` が `ready` になる前（アップロード中/Muxでのトランスコード中）に表示する
/// プレースホルダー。design/system.md 5.1節「処理完了までにタイムラグが生じるため、処理中は
/// プレースホルダーサムネイル＋『処理中』表示をフィードに出す」に対応。
class VideoProcessingPlaceholder extends StatelessWidget {
  const VideoProcessingPlaceholder({super.key, this.thumbnailUrl, required this.status});

  final String? thumbnailUrl;
  final String status;

  String get _statusLabel => switch (status) {
        'pending' => '準備中',
        'uploading' => 'アップロード中',
        'processing' => '処理中',
        'errored' => 'エラーが発生しました',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnailUrl != null)
            Image.network(
              thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.black12),
            )
          else
            Container(color: Colors.black12),
          Container(color: Colors.black38),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status != 'errored') const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 8),
                Text(_statusLabel, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
