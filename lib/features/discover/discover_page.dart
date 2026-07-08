import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'discover_controller.dart';
import 'domain_score.dart';

/// design/product.md 4章「Discover（専門家発掘・ドメイン別ランキング）」画面。
///
/// ドメインを選択し、そのドメインの `domain_scores` ランキング（スコア降順）を表示する。
class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDomain = ref.watch(selectedDomainProvider);
    final rankingAsync = ref.watch(domainRankingProvider(selectedDomain));

    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              initialValue: selectedDomain,
              decoration: const InputDecoration(
                labelText: 'ドメイン',
                border: OutlineInputBorder(),
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
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('まだデータがありません')),
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
                      child: Center(child: Text('ランキングの取得に失敗しました: $error')),
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
String? _badgeLabel(String? badgeTier) {
  return switch (badgeTier) {
    'expert' => 'エキスパート',
    'master' => 'マスター',
    _ => null,
  };
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.rank, required this.domainScore});

  final int rank;
  final DomainScore domainScore;

  @override
  Widget build(BuildContext context) {
    final badgeLabel = _badgeLabel(domainScore.badgeTier);

    return ListTile(
      leading: CircleAvatar(child: Text('$rank')),
      title: Text(domainScore.username ?? '不明なユーザー'),
      subtitle: Text('スコア: ${domainScore.score}'),
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
