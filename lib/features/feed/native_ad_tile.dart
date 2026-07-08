import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/admob_service.dart';

/// design/system.md 10章「マネタイズ（AdMob）実装」。
/// フィード内に一定間隔で差し込むネイティブ広告タイル。
///
/// - 広告ラベル（「広告」）を明示し、投稿と区別できるようにする
/// - ロードに失敗した場合は何も表示しない（フィードのレイアウトを崩さないフォールバック）
class NativeAdTile extends StatefulWidget {
  const NativeAdTile({super.key});

  @override
  State<NativeAdTile> createState() => _NativeAdTileState();
}

class _NativeAdTileState extends State<NativeAdTile> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    final adUnitId = AdMobService.instance.nativeAdUnitId;
    _nativeAd = NativeAd(
      adUnitId: adUnitId,
      factoryId: 'listTile',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _failed = true;
            _nativeAd = null;
          });
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ロード失敗時・未ロード時は何も表示しない（フィードのレイアウトを崩さない）。
    if (_failed || !_isLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '広告',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 4),
          SizedBox(height: 120, child: AdWidget(ad: _nativeAd!)),
        ],
      ),
    );
  }
}
