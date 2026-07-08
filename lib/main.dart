import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/firebase_client.dart';
import 'core/supabase_client.dart';
import 'l10n/gen/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await initSupabase();
  await initFirebase();
  runApp(const ProviderScope(child: RengaApp()));
}

class RengaApp extends ConsumerWidget {
  const RengaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // design/product.md 5章「多言語対応」: 既定言語は英語(en)、日本語(ja)を追加ロケールとして提供する。
    // 端末ロケールが未対応の場合は AppLocalizations が自動的に英語(テンプレート言語)にフォールバックする。
    return MaterialApp.router(
      title: 'Renga',
      theme: buildRengaTheme(),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
