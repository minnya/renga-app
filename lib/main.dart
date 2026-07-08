import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/admob_service.dart';
import 'core/fcm_service.dart';
import 'core/firebase_client.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await initSupabase();
  await initFirebase();
  // design/system.md 4章: FCMの初期化（トークン取得・権限リクエスト・受信ハンドラ登録）。
  await initFcm();
  // design/system.md 10章: AdMob SDKの初期化。
  await initAdMob();
  runApp(const ProviderScope(child: RengaApp()));
}

class RengaApp extends ConsumerWidget {
  const RengaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Renga',
      theme: buildRengaTheme(),
      routerConfig: router,
    );
  }
}
