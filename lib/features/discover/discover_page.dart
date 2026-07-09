import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import 'discover_controller.dart';
import 'domain_post.dart';
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
    final postsAsync = ref.watch(domainPostsProvider(selectedDomain));

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
                  items: domainTaxonomy
                      .map(
                        (key) => DropdownMenuItem(
                          value: key,
                          child: Text(domainDisplayLabel(key)),
                        ),
                      )
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
          // 「このドメインの投稿」セクション＋ランキングリストを1つのスクロール領域にまとめる。
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(domainRankingProvider(selectedDomain));
                ref.invalidate(domainPostsProvider(selectedDomain));
                await Future.wait([
                  ref.read(domainRankingProvider(selectedDomain).future),
                  ref.read(domainPostsProvider(selectedDomain).future),
                ]);
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'このドメインの投稿',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...postsAsync.when(
                    data: (posts) {
                      if (posts.isEmpty) {
                        return [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: Text('まだこのドメインの投稿はありません')),
                          ),
                        ];
                      }
                      return posts
                          .map<Widget>((post) => _DomainPostTile(post: post))
                          .toList();
                    },
                    loading: () => [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                    error: (error, stackTrace) => [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: Text(l10n.discoverLoadError('$error'))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'ランキング',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...rankingAsync.when(
                    data: (ranking) {
                      if (ranking.isEmpty) {
                        return [
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(child: Text(l10n.discoverEmpty)),
                          ),
                        ];
                      }
                      return ranking
                          .asMap()
                          .entries
                          .map<Widget>(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _RankingTile(rank: entry.key + 1, domainScore: entry.value),
                            ),
                          )
                          .toList();
                    },
                    loading: () => [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                    error: (error, stackTrace) => [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: Text(l10n.discoverLoadError('$error'))),
                      ),
                    ],
                  ),
                ],
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

/// design/system.md 6.1節。選択中ドメインに分類された投稿本文を簡易表示するタイル。
/// タップ時の遷移は行わない（一覧表示のみ）。
class _DomainPostTile extends StatelessWidget {
  const _DomainPostTile({required this.post});

  final DomainPost post;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final username = post.username ?? l10n.feedUnknownUser;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    username,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatDateTime(post.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (post.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(post.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}
