import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import 'discover_controller.dart';
import 'domain_score.dart';

/// design/product.md 4章「Discover（専門家発掘・ドメイン別ランキング）」画面。
///
/// ドメインを選択し、そのドメインの `domain_scores` ランキング（スコア降順）を表示する。
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedDomain = ref.watch(selectedDomainProvider);
    final rankingAsync = ref.watch(domainRankingProvider(selectedDomain));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.discoverAppBarTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              initialValue: selectedDomain,
              decoration: InputDecoration(
                labelText: l10n.discoverDomainLabel,
                border: const OutlineInputBorder(),
              ),
              items: domainOptions.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(selectedDomainProvider.notifier).state = value;
                }
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(domainRankingProvider(selectedDomain));
                await ref.read(domainRankingProvider(selectedDomain).future);
              },
              child: rankingAsync.when(
                data: (ranking) {
                  if (ranking.isEmpty) {
                    return ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text(l10n.discoverEmpty)),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    itemCount: ranking.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _RankingTile(rank: index + 1, domainScore: ranking[index]),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text(l10n.discoverLoadError('$error'))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// design/product.md 3.5節「専門家バッジ」（expert/master）のラベル。
String? _badgeLabel(AppLocalizations l10n, String? badgeTier) {
  return switch (badgeTier) {
    'expert' => l10n.discoverBadgeExpert,
    'master' => l10n.discoverBadgeMaster,
    _ => null,
  };
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.rank, required this.domainScore});

  final int rank;
  final DomainScore domainScore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final badgeLabel = _badgeLabel(l10n, domainScore.badgeTier);

    return ListTile(
      leading: CircleAvatar(child: Text('$rank')),
      title: Text(domainScore.username ?? l10n.feedUnknownUser),
      subtitle: Text(l10n.discoverScoreLabel('${domainScore.score}')),
      trailing: badgeLabel != null
          ? Chip(
              label: Text(badgeLabel, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
    );
  }
}
