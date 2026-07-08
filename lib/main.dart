import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/firebase_client.dart';
import 'core/share_intent_service.dart';
import 'core/supabase_client.dart';
import 'features/feed/youtube_utils.dart';
import 'l10n/gen/app_localizations.dart';

/// design/system.md 4章「Firebase連携アーキテクチャ」Crashlytics: 未捕捉の同期エラーは
/// `initFirebase()`内で`FlutterError.onError`/`PlatformDispatcher.instance.onError`から
/// 記録されるが、`runZonedGuarded`のゾーン外に漏れた非同期例外を拾うためにここでも
/// 二重に`recordError`へ送る（Web版はCrashlytics非対応のため送らない）。
void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: '.env');
      await initSupabase();
      await initFirebase();
      runApp(const ProviderScope(child: RengaApp()));
    },
    (error, stack) {
      if (kIsWeb) {
        debugPrint('Unhandled error: $error\n$stack');
        return;
      }
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    },
  );
}

class RengaApp extends ConsumerStatefulWidget {
  const RengaApp({super.key});

  @override
  ConsumerState<RengaApp> createState() => _RengaAppState();
}

class _RengaAppState extends ConsumerState<RengaApp> {
  StreamSubscription<String>? _shareIntentSubscription;

  @override
  void initState() {
    super.initState();
    // design/product.md 3.1節「YouTubeアプリの共有シートに登場」/
    // design/system.md 5.3節。Phase1はAndroidのみ対応
    // （iOSは共有シートに登場させるためにネイティブのShare Extension実装が
    // 別途必要なため、Phase2で対応する）。
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _initShareIntentHandling();
    }
  }

  void _initShareIntentHandling() {
    final shareIntentService = ref.read(shareIntentServiceProvider);

    // アプリが共有シートから新規起動された場合の初期値。
    shareIntentService.getInitialSharedText().then((text) {
      if (text != null) {
        _handleSharedText(shareIntentService, text);
      }
    });

    // アプリ起動中（フォアグラウンド/バックグラウンド）に共有された場合。
    _shareIntentSubscription = shareIntentService.sharedTextStream.listen((text) {
      _handleSharedText(shareIntentService, text);
    });
  }

  /// 共有されたテキストからYouTube URLを検出できた場合、Compose画面へ
  /// 自動プリフィルして遷移する（引用ポスト的に「この動画についてコメントする」導線）。
  void _handleSharedText(ShareIntentService service, String text) {
    final youtubeUrl = extractYoutubeUrl(text);
    if (youtubeUrl == null) {
      service.reset();
      return;
    }
    ref.read(routerProvider).push('/compose', extra: text);
    service.reset();
  }

  @override
  void dispose() {
    _shareIntentSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // design/product.md 5章「多言語対応」: 既定言語は英語(en)、日本語(ja)を追加ロケールとして提供する。
    // 端末ロケールが未対応の場合は AppLocalizations が自動的に英語(テンプレート言語)にフォールバックする。
    return MaterialApp.router(
      title: 'Renga',
      theme: buildRengaLightTheme(),
      darkTheme: buildRengaDarkTheme(),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
