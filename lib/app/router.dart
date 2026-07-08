import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth_state.dart';
import '../core/firebase_client.dart';
import '../features/auth/login_page.dart';
import '../features/auth/signup_page.dart';
import '../features/debug/connection_check_page.dart';
import '../features/discover/discover_page.dart';
import '../features/feed/compose_page.dart';
import '../features/feed/feed_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/profile/profile_page.dart';
import '../features/quiz/quiz_controller.dart';
import '../features/quiz/quiz_page.dart';

const _publicPaths = {'/login', '/signup', '/debug'};

/// design/product.md 4章「情報アーキテクチャ / 画面構成」:
/// [Splash] → [Onboarding: 3問クイズ] → [Home Tab Bar] の必須フローに対応するため、
/// この集合に含まれないパスはオンボーディングクイズ未完了時に `/onboarding-quiz` へ
/// 強制リダイレクトされる。
const _onboardingExemptPaths = {'/login', '/signup', '/debug', '/onboarding-quiz'};

/// アプリ全体のルーティング定義。
///
/// 未ログイン時は `/login` `/signup` `/debug` 以外へのアクセスを `/login` へリダイレクトする。
/// ログイン済みでもオンボーディングクイズ未完了の場合は `/onboarding-quiz` 以外へのアクセスを
/// `/onboarding-quiz` へリダイレクトする。
final routerProvider = Provider<GoRouter>((ref) {
  final authStateAsync = ref.watch(authStateChangesProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefreshListenable(ref),
    // design/system.md 4章「Analytics」: 画面遷移の自動計測。
    observers: [ref.watch(firebaseAnalyticsObserverProvider)],
    redirect: (context, state) {
      // 初回のセッション確認が完了するまではリダイレクトを保留する。
      if (authStateAsync.isLoading) return null;

      final isLoggedIn = ref.read(currentUserProvider) != null;
      final isPublicPath = _publicPaths.contains(state.matchedLocation);

      if (!isLoggedIn && !isPublicPath) return '/login';
      if (isLoggedIn && (state.matchedLocation == '/login' || state.matchedLocation == '/signup')) {
        return '/';
      }

      // design/product.md 4章: ログイン済みかつオンボーディングクイズ未完了の場合、
      // `/onboarding-quiz` 以外へのアクセスを強制的にリダイレクトする。
      if (isLoggedIn && !_onboardingExemptPaths.contains(state.matchedLocation)) {
        final onboardingAsync = ref.read(hasCompletedOnboardingProvider);
        // 判定中は現状維持。完了次第 _AuthRefreshListenable 経由でredirectが再評価される。
        if (onboardingAsync.isLoading) return null;
        // dataでfalseの場合のみ強制遷移。error時やtrueの場合は通常の遷移を継続する
        // (通信エラーでユーザーがロックされてしまうのを避けるためfail-openとする)。
        final hasCompletedOnboarding = onboardingAsync.value ?? true;
        if (!hasCompletedOnboarding) return '/onboarding-quiz';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          // design/product.md 4章「情報アーキテクチャ」: [Splash] 相当。
          // セッション確認/オンボーディング判定が完了するまでは簡易ローディング表示に留め、
          // FeedPageが一瞬表示されてから強制リダイレクトされるちらつきを防ぐ。
          if (authStateAsync.isLoading) {
            return const _RouterLoadingView();
          }
          if (ref.watch(currentUserProvider) != null &&
              ref.watch(hasCompletedOnboardingProvider).isLoading) {
            return const _RouterLoadingView();
          }
          return const FeedPage();
        },
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupPage()),
      GoRoute(
        path: '/compose',
        // design/product.md 3.1節「YouTubeアプリの共有シートに登場」。
        // 共有シート経由の起動時、main.dartが共有テキストを`extra`に載せて`/compose`へ遷移させる。
        builder: (context, state) => ComposePage(initialBody: state.extra as String?),
      ),
      GoRoute(path: '/profile', builder: (context, state) => const ProfilePage()),
      GoRoute(path: '/discover', builder: (context, state) => const DiscoverPage()),
      GoRoute(path: '/notifications', builder: (context, state) => const NotificationsPage()),
      GoRoute(
        path: '/onboarding-quiz',
        builder: (context, state) => const QuizPage(kind: QuizKind.onboarding),
      ),
      GoRoute(
        path: '/daily-quiz',
        builder: (context, state) => const QuizPage(kind: QuizKind.daily),
      ),
      GoRoute(path: '/debug', builder: (context, state) => const ConnectionCheckPage()),
    ],
  );
});

/// 認証状態・オンボーディング完了状態の変化をgo_routerの`refreshListenable`へ橋渡しし、
/// ログイン/ログアウト時、およびオンボーディングクイズ完了時に`redirect`を再評価させる。
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this._ref) {
    _authSubscription = _ref.listen(authStateChangesProvider, (previous, next) {
      notifyListeners();
    });
    // design/product.md 4章: オンボーディングクイズ完了時にもredirectを再評価し、
    // `/onboarding-quiz` からホームへ自動的に遷移させる。
    _onboardingSubscription = _ref.listen(hasCompletedOnboardingProvider, (previous, next) {
      notifyListeners();
    });
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<AuthState>> _authSubscription;
  late final ProviderSubscription<AsyncValue<bool>> _onboardingSubscription;

  @override
  void dispose() {
    _authSubscription.close();
    _onboardingSubscription.close();
    super.dispose();
  }
}

/// design/product.md 4章「情報アーキテクチャ」の[Splash]に相当する簡易ローディング画面。
/// セッション確認/オンボーディング完了判定が終わるまでの間だけ表示される。
class _RouterLoadingView extends StatelessWidget {
  const _RouterLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
