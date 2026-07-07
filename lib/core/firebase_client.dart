import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// design/system.md 4章のFirebase連携（FCM/Remote Config/Crashlytics/Analytics）用の初期化。
/// firebase_options.dart は `flutterfire configure` で生成したもの。
Future<void> initFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}
