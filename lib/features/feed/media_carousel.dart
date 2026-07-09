import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 複数画像を横スクロールで表示するカルーセル。
/// フィード内プレビュー（高さ固定・角丸あり）と全画面表示（高さ可変・角丸なし）の
/// 両方の呼び出しコンテキストに対応する。
class ImageCarousel extends StatefulWidget {
  const ImageCarousel({
    super.key,
    required this.imageUrls,
    this.height = 240,
    this.onTapImage,
    this.initialIndex = 0,
    this.rounded = true,
  });

  final List<String> imageUrls;

  /// 画像枠の高さ。nullの場合は親のサイズいっぱいに広がる（全画面表示用）。
  final double? height;

  /// 画像タップ時、タップされた画像のindexを渡すコールバック。
  final void Function(int index)? onTapImage;

  final int initialIndex;

  /// 角丸表示にするかどうか（全画面表示時はfalseにする）。
  final bool rounded;

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      placeholder: (context, url) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      errorWidget: (context, url, error) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Text('画像を読み込めませんでした'),
        );
      },
    );
  }

  Widget _buildContent() {
    if (widget.imageUrls.length == 1) {
      final url = widget.imageUrls.first;
      return GestureDetector(
        onTap: () => widget.onTapImage?.call(0),
        child: SizedBox.expand(child: _buildImage(url)),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: widget.imageUrls.length,
          onPageChanged: (index) {
            setState(() => _currentIndex = index);
          },
          itemBuilder: (context, index) {
            final url = widget.imageUrls[index];
            return GestureDetector(
              onTap: () => widget.onTapImage?.call(_currentIndex),
              child: SizedBox.expand(child: _buildImage(url)),
            );
          },
        ),
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.imageUrls.length, (index) {
                  final isActive = index == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 8 : 6,
                    height: isActive ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: isActive ? 1.0 : 0.5),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.rounded ? BorderRadius.circular(12) : BorderRadius.zero;

    final content = ClipRRect(
      borderRadius: borderRadius,
      child: _buildContent(),
    );

    if (widget.height == null) {
      return content;
    }

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: content,
    );
  }
}
