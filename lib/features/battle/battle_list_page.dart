import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'battle.dart';
import 'battle_controller.dart';

/// design/product.md 4章「Battle Tab: バトル一覧・進行中バトル・ベット」の一覧画面。
///
/// 進行中(active)/終了(resolved)をタブで切り替え、各カードに賭けTP合計と
/// 決着までの残り時間を表示する。
class BattleListPage extends ConsumerWidget {
  const BattleListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battlesAsync = ref.watch(battleListProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Battle — ロジックチェック'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '進行中'),
              Tab(text: '終了'),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(battleListProvider);
            await ref.read(battleListProvider.future);
          },
          child: battlesAsync.when(
            data: (battles) {
              final active = battles.where((b) => b.isActive).toList();
              final resolved = battles.where((b) => !b.isActive).toList();
              return TabBarView(
                children: [
                  _BattleListView(battles: active, emptyMessage: '進行中のバトルはありません'),
                  _BattleListView(battles: resolved, emptyMessage: '終了したバトルはまだありません'),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text('バトルの取得に失敗しました: $error')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BattleListView extends StatelessWidget {
  const _BattleListView({required this.battles, required this.emptyMessage});

  final List<Battle> battles;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (battles.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(emptyMessage)),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: battles.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _BattleCard(battle: battles[index]),
    );
  }
}

class _BattleCard extends StatelessWidget {
  const _BattleCard({required this.battle});

  final Battle battle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => context.go('/battles/${battle.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${battle.targetPostAuthorUsername ?? '不明なユーザー'} vs '
                      '${battle.challengerPostAuthorUsername ?? '挑戦者'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Chip(
                    label: Text(battle.isActive ? '進行中' : '終了'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (battle.targetPostBody != null)
                Text(
                  battle.targetPostBody!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.paid_outlined, size: 16, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 4),
                  Text('賭けTP合計: ${battle.totalStakeTp.toStringAsFixed(0)}'),
                  const Spacer(),
                  Icon(Icons.timer_outlined, size: 16, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 4),
                  Text(_remainingLabel(battle)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _remainingLabel(Battle battle) {
    if (!battle.isActive) return '決着済み';
    final remaining = battle.remaining;
    if (remaining == Duration.zero) return 'まもなく決着';
    final hours = remaining.inHours;
    if (hours >= 1) return '残り$hours時間';
    return '残り${remaining.inMinutes}分';
  }
}
