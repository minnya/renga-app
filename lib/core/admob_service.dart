import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// design/system.md 10章「マネタイズ（AdMob）実装」に対応するAdMob基盤。
///
/// 広告ユニットIDはハードコードせず`.env`（`ADMOB_*`）から読み込む。
/// 設計上は最終的にFirebase Remote Config経由で配信する想定だが、
/// 実APIキー無しでも動作する構造にするため、まずは`.env`をソースオブトゥルースとし、
/// 値が空の場合はGoogle公式のテスト広告ユニットIDにフォールバックする。
class AdMobService {
  AdMobService._();

  static final AdMobService instance = AdMobService._();

  bool _initialized = false;

  /// `google_mobile_ads`の初期化を行う。`lib/main.dart`から呼び出す。
  Future<void> init() async {
    if (_initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (e) {
      // 実APIキー未設定・ネイティブ設定未完了の開発環境でもアプリ起動を妨げないよう握りつぶす。
      debugPrint('[AdMob] 初期化に失敗しました: $e');
    }
  }

  /// Googleが公開しているテスト用ネイティブ広告ユニットID（Android）。
  static const _testNativeAdUnitIdAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const _testNativeAdUnitIdIOS = 'ca-app-pub-3940256099942544/3986624511';
  static const _testBannerAdUnitIdAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testBannerAdUnitIdIOS = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitialAdUnitIdAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialAdUnitIdIOS = 'ca-app-pub-3940256099942544/4411468910';

  String get nativeAdUnitId => _resolve('ADMOB_NATIVE_AD_UNIT_ID', _testNativeAdUnitId);

  String get bannerAdUnitId => _resolve('ADMOB_BANNER_AD_UNIT_ID', _testBannerAdUnitId);

  String get interstitialAdUnitId =>
      _resolve('ADMOB_INTERSTITIAL_AD_UNIT_ID', _testInterstitialAdUnitId);

  String get _testNativeAdUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? _testNativeAdUnitIdIOS
          : _testNativeAdUnitIdAndroid;

  String get _testBannerAdUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? _testBannerAdUnitIdIOS
          : _testBannerAdUnitIdAndroid;

  String get _testInterstitialAdUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? _testInterstitialAdUnitIdIOS
          : _testInterstitialAdUnitIdAndroid;

  String _resolve(String envKey, String fallback) {
    final value = dotenv.env[envKey];
    if (value == null || value.isEmpty || value.contains('xxxxxxxxxx')) {
      return fallback;
    }
    return value;
  }
}

/// `lib/main.dart`から呼び出すエントリーポイント。
Future<void> initAdMob() => AdMobService.instance.init();
