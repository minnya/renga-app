import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web_only;

/// design/system.md 9章「Google Sign-In」補足。
///
/// google_sign_in_webはプライバシー保護（FedCM）の都合上、`authenticate()`の
/// プログラム的な呼び出しをサポートしない（`UnimplementedError`になる）。
/// Web版ではGIS公式のボタンウィジェットを描画し、ユーザーがそれを直接クリックする
/// 必要がある。サインイン結果は`GoogleSignIn.instance.authenticationEvents`を
/// 購読して受け取る（呼び出し元の`auth_controller.dart`を参照）。
Widget buildGoogleSignInButton() => web_only.renderButton();
