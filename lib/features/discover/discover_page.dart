import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/time_format.dart';
import '../feed/feed_page.dart' show PostTile;
import 'discover_compose_sheet.dart';
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
    final postsAsync = ref.watch(discoverFilteredPostsProvider);
    final discoverPostsAsync = ref.watch(discoverPostsProvider);
    final isTopTier = ref.watch(isTopIntellectTierProvider).value ?? false;

    return Scaffold(
      // design/product.md 2.1節「Discoverの`Create`権限」。上位25%以上のユーザーにのみ
      // Discoverへの新規投稿ボタンを表示する（実際の許可判定はRPC側で行う）。
      floatingActionButton: isTopTier
          ? FloatingActionButton(
              onPressed: () => showDiscoverComposeSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
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
                const SizedBox(height: 12),
                // キーワード検索ボックス（design/product.md 3.16節）
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'キーワードで検索',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  onChanged: (value) {
                    ref.read(discoverSearchKeywordProvider.notifier).state = value;
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
                ref.invalidate(discoverFilteredPostsProvider);
                await Future.wait([
                  ref.read(domainRankingProvider(selectedDomain).future),
                  ref.read(discoverFilteredPostsProvider.future),
                ]);
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  // design/product.md 2.1節・3.4節。Discoverの新規投稿（Create権限保持者による
                  // 投稿・Feedからの引き上げ）とオプトイン型の真偽投票UI。
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'Discover投稿',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...discoverPostsAsync.when(
                    data: (posts) {
                      if (posts.isEmpty) {
                        return [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: Text('まだDiscover投稿はありません')),
                          ),
                        ];
                      }
                      return posts.map<Widget>((post) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            // design/product.md 3.4節。真偽投票UIはPostTile内に統合済みのため、
                            // ここでは個別に描画しない。
                            child: PostTile(post: post),
                          ),
                        );
                      }).toList();
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
                        child: Center(child: Text('Discover投稿の取得に失敗しました: $error')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
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
                  GestureDetector(
                    onTap: () => context.push('/profile/${domainScore.userId}'),
                    child: Text(
                      username,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
      child: InkWell(
        onTap: () => context.push('/posts/${post.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push('/profile/${post.authorId}'),
                      child: Text(
                        username,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Text(
                    relativeTimeLabel(l10n, post.createdAt),
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
      ),
    );
  }
}
