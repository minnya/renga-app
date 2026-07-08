import 'package:flutter/widgets.dart';

import 'google_signin_button_stub.dart'
    if (dart.library.js_interop) 'google_signin_button_web.dart' as impl;

/// design/system.md 9章「Google Sign-In」。
///
/// Web版はGIS公式ボタンの描画が必須（`auth_controller.dart`のコメント参照）なため、
/// プラットフォームごとに実装を出し分ける（条件付きインポート）。
/// 呼び出し前に`GoogleSignIn.instance.initialize(...)`が完了している必要がある。
Widget buildGoogleSignInButton() => impl.buildGoogleSignInButton();
