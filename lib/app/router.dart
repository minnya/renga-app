import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth_state.dart';
import '../core/firebase_client.dart';
import '../features/auth/login_page.dart';
import '../features/auth/signup_page.dart';
import '../features/battle/battle_detail_page.dart';
import '../features/battle/battle_list_page.dart';
import '../features/debug/connection_check_page.dart';
import '../features/discover/discover_page.dart';
import '../features/feed/compose_page.dart';
import '../features/feed/feed_page.dart';
import '../features/feed/post_detail_page.dart';
import '../features/messages/conversation_page.dart';
import '../features/messages/messages_list_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/profile/profile_page.dart';
import '../features/quiz/quiz_controller.dart';
import '../features/quiz/quiz_page.dart';
import '../features/settings/delete_account_page.dart';
import '../features/settings/display_settings_page.dart';
import '../features/settings/email_page.dart';
import '../features/settings/language_settings_page.dart';
import '../features/settings/password_change_page.dart';
import '../features/settings/profile_edit_page.dart';
import '../features/settings/settings_page.dart';
import 'main_shell.dart';

const _publicPaths = {'/login', '/signup', '/debug'};

/// design/product.md 4章「ページ遷移のアニメーション」。Instagram/X標準相当の
/// フェード＋わずかな下からのスライドで画面遷移する共通トランジション。
/// タブ切り替え（[StatefulShellRoute]のブランチ）には適用しない
/// （ボトムナビのタブ切り替えは即時表示がInstagram/Xの標準挙動のため）。
CustomTransitionPage<void> _fadeSlidePage(BuildContext context, GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

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
    // 未定義のパス（Web版で古いURLがブックマーク/共有された場合、存在しない通知
    // ディープリンク等）にアクセスされた際、GoExceptionでアプリごとクラッシュさせず
    // ホームへリダイレクトする（design/product.md 4章のIA外のパスへのフォールバック）。
    onException: (context, state, router) => router.go('/'),
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
      // design/product.md 4章「情報アーキテクチャ」: InstagramやX(Twitter)と同じ
      // ボトムナビゲーション＋タブ構造。Feed/Discover/Battle/Profileの4ブランチは
      // それぞれ独立したナビゲーションスタック・スクロール位置を保持する
      // (`StatefulShellRoute.indexedStack`)。Composeはタブに含めず、中央ボタンから
      // 常にフルスクリーンで`push`する（[MainShell]参照）。
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // design/product.md 4章「情報アーキテクチャ」: [Splash] 相当。
          // セッション確認/オンボーディング判定が完了するまでは簡易ローディング表示に留め、
          // ホームが一瞬表示されてから強制リダイレクトされるちらつきを防ぐ。
          if (authStateAsync.isLoading) {
            return const _RouterLoadingView();
          }
          if (ref.watch(currentUserProvider) != null &&
              ref.watch(hasCompletedOnboardingProvider).isLoading) {
            return const _RouterLoadingView();
          }
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (context, state) => const FeedPage())]),
          StatefulShellBranch(
            routes: [GoRoute(path: '/discover', builder: (context, state) => const DiscoverPage())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/battles',
                builder: (context, state) => const BattleListPage(),
                routes: [
                  GoRoute(
                    path: ':battleId',
                    pageBuilder: (context, state) => _fadeSlidePage(
                      context,
                      state,
                      BattleDetailPage(battleId: state.pathParameters['battleId']!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfilePage(),
                routes: [
                  // design/system.md 15章「ダイレクトメッセージ（DM）」。他ユーザーの
                  // プロフィールをID指定で表示し、DM開始ボタンを提供する導線。
                  GoRoute(
                    path: ':userId',
                    pageBuilder: (context, state) => _fadeSlidePage(
                      context,
                      state,
                      ProfilePage(userId: state.pathParameters['userId']),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/login', pageBuilder: (context, state) => _fadeSlidePage(context, state, const LoginPage())),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => _fadeSlidePage(context, state, const SignupPage()),
      ),
      // design/product.md 3.12節「投稿詳細（スレッド表示）」。投稿を親としてコメントを
      // 下に並べるX/Instagram風の詳細画面。
      GoRoute(
        path: '/posts/:postId',
        pageBuilder: (context, state) => _fadeSlidePage(
          context,
          state,
          PostDetailPage(postId: state.pathParameters['postId']!),
        ),
      ),
      GoRoute(
        path: '/compose',
        // design/product.md 3.1節「YouTubeアプリの共有シートに登場」。
        // 共有シート経由の起動時、main.dartが共有テキストを`extra`に載せて`/compose`へ遷移させる。
        pageBuilder: (context, state) =>
            _fadeSlidePage(context, state, ComposePage(initialBody: state.extra as String?)),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => _fadeSlidePage(context, state, const NotificationsPage()),
      ),
      // design/system.md 15章「ダイレクトメッセージ（DM）」。DM一覧・会話詳細画面。
      GoRoute(
        path: '/messages',
        pageBuilder: (context, state) => _fadeSlidePage(context, state, const MessagesListPage()),
        routes: [
          GoRoute(
            path: ':conversationId',
            pageBuilder: (context, state) => _fadeSlidePage(
              context,
              state,
              ConversationPage(conversationId: state.pathParameters['conversationId']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _fadeSlidePage(context, state, const SettingsPage()),
        // design/product.md 3.11節: Settings画面自体は設定項目への遷移リストのみを表示し、
        // 各行のタップで専用のサブページへ`push`する。
        routes: [
          GoRoute(
            path: 'email',
            pageBuilder: (context, state) => _fadeSlidePage(context, state, const EmailPage()),
          ),
          GoRoute(
            path: 'profile',
            pageBuilder: (context, state) => _fadeSlidePage(context, state, const ProfileEditPage()),
          ),
          GoRoute(
            path: 'password',
            pageBuilder: (context, state) => _fadeSlidePage(context, state, const PasswordChangePage()),
          ),
          GoRoute(
            path: 'delete-account',
            pageBuilder: (context, state) => _fadeSlidePage(context, state, const DeleteAccountPage()),
          ),
          GoRoute(
            path: 'display',
            pageBuilder: (context, state) => _fadeSlidePage(context, state, const DisplaySettingsPage()),
          ),
          GoRoute(
            path: 'language',
            pageBuilder: (context, state) => _fadeSlidePage(context, state, const LanguageSettingsPage()),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding-quiz',
        pageBuilder: (context, state) => _fadeSlidePage(context, state, const QuizPage(kind: QuizKind.onboarding)),
      ),
      GoRoute(
        path: '/daily-quiz',
        pageBuilder: (context, state) => _fadeSlidePage(context, state, const QuizPage(kind: QuizKind.daily)),
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
