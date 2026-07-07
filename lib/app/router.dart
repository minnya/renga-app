import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/debug/connection_check_page.dart';

/// アプリ全体のルーティング定義。
///
/// `/login` `/signup` `/profile` `/compose` は feature/auth, feature/profile, feature/feed の
/// 各実装がマージされ次第、プレースホルダーから実画面に差し替える（design/plan参照）。
/// 認証状態によるリダイレクトも、feature/auth マージ後にここへ配線する。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _PlaceholderPage(title: 'Feed')),
      GoRoute(
        path: '/login',
        builder: (context, state) => const _PlaceholderPage(title: 'Login'),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const _PlaceholderPage(title: 'Sign up'),
      ),
      GoRoute(
        path: '/compose',
        builder: (context, state) => const _PlaceholderPage(title: 'Compose'),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const _PlaceholderPage(title: 'Profile'),
      ),
      GoRoute(
        path: '/debug',
        builder: (context, state) => const ConnectionCheckPage(),
      ),
    ],
  );
});

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$title は実装待ちです'),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go('/debug'),
              child: const Text('基盤動作確認へ'),
            ),
          ],
        ),
      ),
    );
  }
}
