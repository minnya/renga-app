import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final battlesAsync = ref.watch(battleListProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.battleListAppBarTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.battleTabActive),
              Tab(text: l10n.battleTabResolved),
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
                  _BattleListView(battles: active, emptyMessage: l10n.battleListEmptyActive),
                  _BattleListView(battles: resolved, emptyMessage: l10n.battleListEmptyResolved),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text(l10n.battleListLoadError('$error'))),
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
    final l10n = AppLocalizations.of(context);
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
                      '${battle.targetPostAuthorUsername ?? l10n.feedUnknownUser} vs '
                      '${battle.challengerPostAuthorUsername ?? l10n.battleChallengerFallback}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Chip(
                    label: Text(battle.isActive ? l10n.battleTabActive : l10n.battleTabResolved),
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
                  Text(l10n.battleStakeTotalLabel(battle.totalStakeTp.toStringAsFixed(0))),
                  const Spacer(),
                  Icon(Icons.timer_outlined, size: 16, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 4),
                  Text(_remainingLabel(l10n, battle)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _remainingLabel(AppLocalizations l10n, Battle battle) {
    if (!battle.isActive) return l10n.battleRemainingResolved;
    final remaining = battle.remaining;
    if (remaining == Duration.zero) return l10n.battleRemainingSoon;
    final hours = remaining.inHours;
    if (hours >= 1) return l10n.battleRemainingHours(hours);
    return l10n.battleRemainingMinutes(remaining.inMinutes);
  }
}
