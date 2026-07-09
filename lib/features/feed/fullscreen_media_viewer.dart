import 'package:flutter/material.dart';

import 'media_carousel.dart';
import 'video_player_widget.dart';

/// 投稿メディア（画像・動画）を全画面表示するビューア。
/// design/product.md 3.13節に基づき、Navigator.pushで開くページとして使用する。
class FullscreenMediaViewer extends StatelessWidget {
  const FullscreenMediaViewer({
    super.key,
    this.imageUrls,
    this.initialImageIndex = 0,
    this.videoPlaybackId,
  });

  /// 画像投稿の場合の画像URLリスト。
  final List<String>? imageUrls;

  final int initialImageIndex;

  /// 動画投稿の場合のMux再生ID。
  final String? videoPlaybackId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onVerticalDragUpdate: (_) {},
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() > 300) {
            Navigator.pop(context);
          }
        },
        child: Stack(
          children: [
            Positioned.fill(child: _buildContent()),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (imageUrls != null && imageUrls!.isNotEmpty) {
      return ImageCarousel(
        imageUrls: imageUrls!,
        height: null,
        rounded: false,
        initialIndex: initialImageIndex,
      );
    }

    if (videoPlaybackId != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: MuxVideoPlayerWidget(
            playbackId: videoPlaybackId!,
            autoPlay: true,
            isPreview: false,
          ),
        ),
      );
    }

    return Container();
  }
}
