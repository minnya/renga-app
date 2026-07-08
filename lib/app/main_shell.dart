import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// design/product.md 4章「情報アーキテクチャ」。InstagramやX(Twitter)と同じ
/// 「ボトムナビゲーション＋タブ」構造。各タブ(Feed/Discover/Battle/Profile)は
/// `StatefulShellRoute.indexedStack`で独立したナビゲーションスタックとスクロール位置を保持する。
///
/// Composeはタブとして状態を保持せず、X/Instagramの投稿ボタンと同様に中央から
/// 常に新規のフルスクリーン画面として`push`する（[navigationShell]のブランチ切替は行わない）。
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _composeTabIndex = 2;

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
          BottomNavigationBarItem(icon: Icon(Icons.add_box_outlined), label: 'Compose'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt_outlined), activeIcon: Icon(Icons.bolt), label: 'Battle'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  /// ボトムナビゲーションのインデックス(5項目、中央がCompose)と、
  /// [StatefulShellRoute]のブランチインデックス(4ブランチ、Composeを含まない)の対応付け。
  int _currentIndexFor(int branchIndex) => branchIndex < _composeTabIndex ? branchIndex : branchIndex + 1;

  void _onTap(BuildContext context, int tappedIndex) {
    if (tappedIndex == _composeTabIndex) {
      context.push('/compose');
      return;
    }
    final branchIndex = tappedIndex < _composeTabIndex ? tappedIndex : tappedIndex - 1;
    navigationShell.goBranch(branchIndex, initialLocation: branchIndex == navigationShell.currentIndex);
  }
}
