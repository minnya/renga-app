import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';

/// design/system.md 4章のFirebase連携（FCM/Remote Config/Crashlytics/Analytics）用の初期化。
/// firebase_options.dart は `flutterfire configure` で生成したもの。
///
/// Crashlytics（クラッシュ・非致命的エラー収集）はWeb版が正式サポート外のため、
/// `kIsWeb` の場合は初期化・エラーハンドラの配線をスキップする。
/// `main.dart` 側では `runZonedGuarded` により `FirebaseCrashlytics.instance.recordError`へ
/// 未捕捉の非同期例外を送るため、`FlutterError.onError` と
/// `PlatformDispatcher.instance.onError` をここで設定する。
Future<void> initFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kIsWeb) {
    // WebはCrashlytics非対応のため、標準のFlutterエラーハンドラのままにしておく。
    return;
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

/// design/system.md 4章「Analytics」: 画面遷移・主要アクション（投稿等）のイベント計測に使う
/// [FirebaseAnalytics] のインスタンスを提供するProvider。
final firebaseAnalyticsProvider = Provider<FirebaseAnalytics>((ref) {
  return FirebaseAnalytics.instance;
});

/// go_routerの`observers`へ登録し、画面遷移を自動的にAnalyticsへ送るためのProvider。
final firebaseAnalyticsObserverProvider = Provider<FirebaseAnalyticsObserver>((ref) {
  return FirebaseAnalyticsObserver(analytics: ref.watch(firebaseAnalyticsProvider));
});
