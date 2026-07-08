import 'package:flutter/widgets.dart';

/// 非Web（Android/iOS）向けスタブ。実際には[kIsWeb]が真の場合のみ
/// `google_signin_button_web.dart`側の実装が使われるため、ここは呼ばれない想定。
Widget buildGoogleSignInButton() => const SizedBox.shrink();
