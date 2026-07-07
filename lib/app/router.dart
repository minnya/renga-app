import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth_state.dart';
import '../features/auth/login_page.dart';
import '../features/auth/signup_page.dart';
import '../features/debug/connection_check_page.dart';
import '../features/feed/compose_page.dart';
import '../features/feed/feed_page.dart';
import '../features/profile/profile_page.dart';
import '../features/quiz/quiz_controller.dart';
import '../features/quiz/quiz_page.dart';

const _publicPaths = {'/login', '/signup', '/debug'};

/// アプリ全体のルーティング定義。
///
/// 未ログイン時は `/login` `/signup` `/debug` 以外へのアクセスを `/login` へリダイレクトする。
final routerProvider = Provider<GoRouter>((ref) {
  final authStateAsync = ref.watch(authStateChangesProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefreshListenable(ref),
    redirect: (context, state) {
      // 初回のセッション確認が完了するまではリダイレクトを保留する。
      if (authStateAsync.isLoading) return null;

      final isLoggedIn = ref.read(currentUserProvider) != null;
      final isPublicPath = _publicPaths.contains(state.matchedLocation);

      if (!isLoggedIn && !isPublicPath) return '/login';
      if (isLoggedIn && (state.matchedLocation == '/login' || state.matchedLocation == '/signup')) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const FeedPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupPage()),
      GoRoute(path: '/compose', builder: (context, state) => const ComposePage()),
      GoRoute(path: '/profile', builder: (context, state) => const ProfilePage()),
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

/// 認証状態の変化をgo_routerの`refreshListenable`へ橋渡しし、
/// ログイン/ログアウト時に`redirect`を再評価させる。
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(this._ref) {
    _subscription = _ref.listen(authStateChangesProvider, (previous, next) {
      notifyListeners();
    });
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<AuthState>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
