import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// design/product.md 4章「情報アーキテクチャ」。InstagramやX(Twitter)と同じ
/// 「ボトムナビゲーション＋タブ」構造。各タブ(Feed/Discover/Battle/Profile)は
/// `StatefulShellRoute.indexedStack`で独立したナビゲーションスタックとスクロール位置を保持する。
///
/// Messagesはタブとして状態を保持せず、中央のボタンから常に新規のフルスクリーン画面として
/// `push`する（[navigationShell]のブランチ切替は行わない）。Composeはフィード画面上部の
/// ボタンから開く。
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _messagesTabIndex = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndexFor(navigationShell.currentIndex),
        onTap: (tappedIndex) => _onTap(context, tappedIndex),
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

  /// ボトムナビゲーションのインデックス(5項目、中央がMessages)と、
  /// [StatefulShellRoute]のブランチインデックス(4ブランチ、Messagesを含まない)の対応付け。
  int _currentIndexFor(int branchIndex) => branchIndex < _messagesTabIndex ? branchIndex : branchIndex + 1;

  void _onTap(BuildContext context, int tappedIndex) {
    if (tappedIndex == _messagesTabIndex) {
      context.push('/messages');
      return;
    }
    final branchIndex = tappedIndex < _messagesTabIndex ? tappedIndex : tappedIndex - 1;
    navigationShell.goBranch(branchIndex, initialLocation: branchIndex == navigationShell.currentIndex);
  }
}
