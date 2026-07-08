import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'supabase_client.dart';

/// design/system.md 4章「Firebase連携アーキテクチャ」の通知アーキテクチャに対応するFCM基盤。
///
/// - アプリ起動時に通知権限をリクエストし、FCMトークンを取得する
/// - ログイン中ユーザーであれば取得・更新（`onTokenRefresh`含む）のたびに`device_tokens`へupsertする
/// - フォアグラウンド/バックグラウンド/終了状態の3パターンの受信ハンドラの雛形を用意する
///
/// 通知タップ時のディープリンク解決はgo_router側で行う想定のため、ここでは
/// ペイロード（`message.data`）の受け渡しのみ担当する。

/// バックグラウンド/終了状態で通知を受信した際に呼ばれるハンドラ。
/// トップレベル関数（もしくは`@pragma('vm:entry-point')`付きのstatic関数）である必要があるため、
/// クラス外に定義する。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // バックグラウンド/終了状態では、UIの更新は行わずログのみに留める。
  // 必要であればここでローカル通知の追加表示やデータの事前フェッチを行う。
  debugPrint('[FCM] バックグラウンドで通知を受信しました: ${message.messageId}');
}

class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// FCMの初期化を行う。`lib/main.dart`の`initFirebase()`の後に呼び出す。
  Future<void> init() async {
    // 終了状態から通知タップで起動された場合のバックグラウンドハンドラを登録する。
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 通知権限をリクエストする（iOSでは必須。Androidも13以降は必須）。
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // フォアグラウンド時にもバナー表示できるようにする（iOS）。
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 初回トークン取得・登録。
    final token = await _messaging.getToken();
    if (token != null) {
      await _syncDeviceToken(token);
    }

    // トークンリフレッシュ時（端末の再インストール・OS更新等）にも同期する。
    _messaging.onTokenRefresh.listen(_syncDeviceToken);

    // フォアグラウンド受信ハンドラ。
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // バックグラウンドで通知をタップしてアプリがフォアグラウンドに復帰したときのハンドラ。
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // 終了状態から通知タップで起動された場合の初期メッセージを確認する。
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// フォアグラウンド状態で通知を受信した際の処理。
  /// アプリがアクティブなためOS標準の通知バナーは出ないので、必要であればここで
  /// アプリ内バナー等を表示する（雛形のためログのみ）。
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM] フォアグラウンドで通知を受信しました: ${message.notification?.title}');
  }

  /// 通知タップ時の処理。`message.data`のルートパスをもとにgo_routerでディープリンクする想定。
  void _handleNotificationTap(RemoteMessage message) {
    final route = message.data['route'];
    debugPrint('[FCM] 通知がタップされました。遷移先: $route');
    // TODO: go_routerのグローバルなrouterProvider経由でディープリンクを解決する。
  }

  /// 取得したFCMトークンをログイン中ユーザーの`device_tokens`テーブルへupsertする。
  /// 未ログイン時は何もしない（ログイン後の初期化タイミングで再度呼び出す運用を想定）。
  Future<void> _syncDeviceToken(String token) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      await supabase.from('device_tokens').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'platform': _platformName(),
        'app_version': _appVersionPlaceholder,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fcm_token');
    } catch (e) {
      debugPrint('[FCM] device_tokensへの同期に失敗しました: $e');
    }
  }

  String _platformName() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  // app_versionはpackage_info_plus等の導入後に実値へ差し替える想定のプレースホルダー。
  static const _appVersionPlaceholder = '1.0.0';
}

/// `lib/main.dart`から呼び出すエントリーポイント。
Future<void> initFcm() => FcmService.instance.init();
