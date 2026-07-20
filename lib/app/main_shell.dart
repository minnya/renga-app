import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth_state.dart';
import '../features/feed/feed_page.dart' show confirmAndStartDailyQuiz;
import '../features/quiz/quiz_controller.dart';
import '../l10n/gen/app_localizations.dart';

/// design/product.md 4章「情報アーキテクチャ」。InstagramやX(Twitter)と同じ
/// 「ボトムナビゲーション＋タブ」構造。各タブ(Feed/Discover/Messages/Profile)の4タブは
/// `StatefulShellRoute.indexedStack`で独立したナビゲーションスタックとスクロール位置を保持する。
/// Messages一覧もこのタブの一部としてスタック内に保持され、他タブと同じく即時切替される
/// (個別DM会話画面はタブ内から`push`されるフルスクリーン画面のまま)。
/// Composeはフィード画面上部のボタンから開く。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowDailyQuizPrompt());
  }

  /// design/product.md 3.15節「アプリ起動時のデイリークイズ確認ダイアログ」。
  /// 未受験の場合のみ、1日1回を上限に確認ダイアログを表示する
  /// （表示済みかどうかはSharedPreferencesにUTC日付で永続化し、アプリ再起動後も当日中は再表示しない）。
  Future<void> _maybeShowDailyQuizPrompt() async {
    if (ref.read(currentUserProvider) == null) return;

    final hasCompleted = await ref.read(hasCompletedDailyTodayProvider.future);
    if (hasCompleted || !mounted) return;

    if (!await shouldShowDailyQuizPrompt() || !mounted) return;
    await markDailyQuizPromptShown();
    if (!mounted) return;

    await confirmAndStartDailyQuiz(context, AppLocalizations.of(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: widget.navigationShell.currentIndex,
        onTap: (tappedIndex) => widget.navigationShell.goBranch(
          tappedIndex,
          initialLocation: tappedIndex == widget.navigationShell.currentIndex,
        ),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
