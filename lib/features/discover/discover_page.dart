import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import 'discover_controller.dart';
import 'domain_score.dart';

/// design/product.md 4章「Discover（専門家発掘・ドメイン別ランキング）」画面。
///
/// ドメインを選択し、そのドメインの `domain_scores` ランキング（スコア降順）を表示する。
/// InstagramのExplore（発見）タブに近いUI設計。
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedDomain = ref.watch(selectedDomainProvider);
    final rankingAsync = ref.watch(domainRankingProvider(selectedDomain));

    return Scaffold(
      body: Column(
        children: [
          // ヘッダーセクション（大きめの見出し・余白。Instagram風）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.discoverAppBarTitle,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                // ドメイン選択ドロップダウン
                DropdownButtonFormField<String>(
                  initialValue: selectedDomain,
                  decoration: InputDecoration(
                    labelText: l10n.discoverDomainLabel,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
              ],
            ),
          ),
          // ランキングリスト
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: ranking.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
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

  /// 順位に応じたメダル色（上位3位のみ）。
  Color? _getMedalColor() {
    return switch (rank) {
      1 => const Color(0xFFFFD700), // Gold
      2 => const Color(0xFFC0C0C0), // Silver
      3 => const Color(0xFFCD7F32), // Bronze
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final badgeLabel = _badgeLabel(l10n, domainScore.badgeTier);
    final medalColor = _getMedalColor();
    final username = domainScore.username ?? l10n.feedUnknownUser;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // ランク数字を円形のメダルで表示（上位3位は色付け）
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: medalColor ?? theme.colorScheme.surfaceContainerHighest,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: medalColor != null
                        ? Colors.black87
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // ユーザー名とスコア
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.discoverScoreLabel('${domainScore.score}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // エキスパート・マスターバッジ
            if (badgeLabel != null)
              Chip(
                label: Text(badgeLabel),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ),
    );
  }
}
