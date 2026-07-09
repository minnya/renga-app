import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// design/product.md 4章「情報アーキテクチャ」。InstagramやX(Twitter)と同じ
/// 「ボトムナビゲーション＋タブ」構造。各タブ(Feed/Discover/Messages/Battle/Profile)は
/// `StatefulShellRoute.indexedStack`で独立したナビゲーションスタックとスクロール位置を保持する。
/// Messages一覧もこのタブの一部としてスタック内に保持され、他タブと同じく即時切替される
/// (個別DM会話画面はタブ内から`push`されるフルスクリーン画面のまま)。
/// Composeはフィード画面上部のボタンから開く。
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (tappedIndex) =>
            navigationShell.goBranch(tappedIndex, initialLocation: tappedIndex == navigationShell.currentIndex),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt_outlined), activeIcon: Icon(Icons.bolt), label: 'Battle'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
