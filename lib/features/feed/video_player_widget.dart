import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 直近に読み込んだ動画のVideoPlayerControllerをplaybackId単位でLRUキャッシュする。
/// フィードのスクロールで画面外に出た動画をすぐには破棄せず、再スクロールで戻ってきた際に
/// 再ダウンロード・再初期化なしで再生を継続できるようにする。
class _VideoControllerCache {
  _VideoControllerCache._();

  static const _maxSize = 6;
  static final Map<String, VideoPlayerController> _pool = {};
  static final List<String> _order = [];

  /// キャッシュから追い出されて破棄された動画も含め、直近の再生位置を覚えておく
  /// （スクロールで再び画面内に戻った際、その位置から再生を再開するため）。
  static final Map<String, Duration> _lastPositions = {};

  static VideoPlayerController? take(String playbackId) {
    final controller = _pool.remove(playbackId);
    if (controller == null) return null;
    _order.remove(playbackId);
    return controller;
  }

  static Duration? lastPosition(String playbackId) => _lastPositions[playbackId];

  static void put(String playbackId, VideoPlayerController controller) {
    if (controller.value.isInitialized) {
      _lastPositions[playbackId] = controller.value.position;
    }
    _pool[playbackId] = controller;
    _order
      ..remove(playbackId)
      ..add(playbackId);
    while (_order.length > _maxSize) {
      final evictedKey = _order.removeAt(0);
      _pool.remove(evictedKey)?.dispose();
    }
  }
}

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
    _controller = _obtainController(widget.playbackId);
    _initializeFuture = _initialize(_controller);
  }

  /// 直近に読み込んだ動画は [_VideoControllerCache] から再利用し、
  /// 再スクロールでの再ダウンロード・再初期化を避ける。
  VideoPlayerController _obtainController(String playbackId) {
    return _VideoControllerCache.take(playbackId) ??
        VideoPlayerController.networkUrl(
          Uri.parse('https://stream.mux.com/$playbackId.m3u8'),
        );
  }

  Future<void> _initialize(VideoPlayerController controller) async {
    if (!controller.value.isInitialized) {
      await controller.initialize();
      // キャッシュに残っていた場合はコントローラー自体が再生位置を保持しているが、
      // キャッシュ上限超過等で一度破棄された動画は、新規コントローラーへ最後の再生位置を復元する。
      final remembered = _VideoControllerCache.lastPosition(widget.playbackId);
      if (remembered != null && remembered > Duration.zero) {
        await controller.seekTo(remembered);
      }
    }
    if (!mounted || controller != _controller) return;
    if (widget.isPreview) {
      await controller.setLooping(true);
      await controller.setVolume(0);
    } else {
      await controller.setLooping(false);
      await controller.setVolume(1);
    }
    if (widget.autoPlay) {
      await controller.play();
    } else {
      await controller.pause();
    }
  }

  @override
  void didUpdateWidget(covariant MuxVideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playbackId != oldWidget.playbackId) {
      final oldController = _controller;
      final newController = _obtainController(widget.playbackId);
      setState(() {
        _controller = newController;
        _initializeFuture = _initialize(newController);
      });
      _VideoControllerCache.put(oldWidget.playbackId, oldController);
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
    _controller.pause();
    // 画面外に出てもコントローラーは破棄せずキャッシュへ戻す（キャッシュ上限超過分のみ破棄）。
    _VideoControllerCache.put(widget.playbackId, _controller);
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
            CachedNetworkImage(
              imageUrl: thumbnailUrl!,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(color: Colors.black12),
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
