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
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: _BattleEmptyPlaceholder(emptyMessage: emptyMessage),
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

/// design/product.md 3.4節・3.6節・3.7節「ステーキングとロジックチェック」「デマ対策・拡散抑止」
/// 「3ストライク・累積ペナルティ」の要旨を、バトルがまだ無いときの空状態プレースホルダとして表示する。
/// 別ページ・別シートは設けず、データが無い箇所にそのまま説明文を差し込む。
class _BattleEmptyPlaceholder extends StatelessWidget {
  const _BattleEmptyPlaceholder({required this.emptyMessage});

  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            emptyMessage,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 24),
        Text(l10n.battleInfoSheetTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          l10n.battleInfoSheetIntro,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _BattleInfoStep(title: l10n.battleInfoSheetStep1Title, body: l10n.battleInfoSheetStep1Body),
        _BattleInfoStep(title: l10n.battleInfoSheetStep2Title, body: l10n.battleInfoSheetStep2Body),
        _BattleInfoStep(title: l10n.battleInfoSheetStep3Title, body: l10n.battleInfoSheetStep3Body),
        _BattleInfoStep(title: l10n.battleInfoSheetStep4Title, body: l10n.battleInfoSheetStep4Body),
      ],
    );
  }
}

class _BattleInfoStep extends StatelessWidget {
  const _BattleInfoStep({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            battle.targetPostAuthorUsername ?? l10n.feedUnknownUser,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(
                            Icons.bolt,
                            size: 16,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            battle.challengerPostAuthorUsername ?? l10n.battleChallengerFallback,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.paid_outlined, size: 16, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 4),
                  Text(
                    l10n.battleStakeTotalLabel(battle.totalStakeTp.toStringAsFixed(0)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Icon(Icons.timer_outlined, size: 16, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 4),
                  Text(
                    _remainingLabel(l10n, battle),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
