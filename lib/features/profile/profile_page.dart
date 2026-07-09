import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/info_bottom_sheet.dart';
import '../../shared/iq_format.dart';
import '../../shared/score_format.dart';
import '../feed/fullscreen_media_viewer.dart';
import '../feed/intellect_badge.dart';
import '../messages/messages_controller.dart';
import 'profile_controller.dart';
import 'profile_edit_sheet.dart';
import 'score_history_chart_sheet.dart';

/// プロフィール表示・編集画面。
///
/// - 未ログイン時: ログイン画面へ誘導する案内を表示する。
/// - ログイン時: 自分の `profiles` 行を取得し、常に読み取り専用ビューを表示する。
///   編集は「編集」ボタンから開く [ProfileEditSheet]（ボトムシート）で行う
///   （design/product.md 3.10節）。
/// - [userId] を指定すると他ユーザーのプロフィールを表示する（design/system.md 15章の
///   DM開始導線用）。未指定時は常に自分自身のプロフィールを表示する（ボトムナビのタブ）。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key, this.userId});

  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context);
    final targetUserId = userId ?? currentUser?.id;
    final isOwnProfile = targetUserId != null && targetUserId == currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileAppBarTitle),
        // design/product.md 3.11節「Settings画面」。Profile画面の歯車アイコンから遷移する。
        actions: [
          if (isOwnProfile)
            IconButton(
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: targetUserId == null
          ? _SignedOutView()
          : _SignedInProfileView(userId: targetUserId, isOwnProfile: isOwnProfile),
    );
  }
}

class _SignedOutView extends StatelessWidget {
  const _SignedOutView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.profileSignedOutMessage),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/login'),
              child: Text(l10n.profileGoToLogin),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInProfileView extends ConsumerWidget {
  const _SignedInProfileView({required this.userId, required this.isOwnProfile});

  final String userId;
  final bool isOwnProfile;

  /// design/system.md 15章「ダイレクトメッセージ（DM）」。他ユーザーのプロフィールから
  /// DMを開始する導線。`get_or_create_dm_conversation` RPCで会話IDを取得し会話詳細へ遷移する。
  Future<void> _handleStartConversation(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final conversationId = await ref.read(messagesControllerProvider).startConversation(userId);
      if (!context.mounted) return;
      context.push('/messages/$conversationId');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.messagesStartConversationError('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider(userId));
    // design/system.md 2章「平均値・日次推移」。読み込み中/失敗時は比較表示を省略するだけで
    // メイン表示をブロックしないよう、値のみ(.value)を参照する。
    final scoreStats = ref.watch(scoreStatsProvider).value;
    final scoreHistory = ref.watch(scoreHistoryProvider(userId)).value ?? const [];
    final theme = Theme.of(context);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Text(l10n.profileLoadError('$error')),
      ),
      data: (profile) {
        final avatarUrl = (profile['avatar_url'] as String?);
        final displayName = (profile['display_name'] as String?) ?? '';
        final username = (profile['username'] as String?) ?? '';
        final bio = (profile['bio'] as String?) ?? '';
        final websiteUrl = (profile['website_url'] as String?) ?? '';
        final location = (profile['location'] as String?) ?? '';
        final influenceScore = profile['influence_score'] ?? 0;
        final influencePercentile = profile['influence_percentile'] ?? 0;
        final intellectScore = profile['intellect_score'] ?? 0;
        final intellectPercentile = profile['intellect_percentile'] as num?;
        final tpBalance = profile['tp_balance'] ?? 0;
        final strikeCount = profile['strike_count'] ?? 0;

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildAvatarSection(
                  context,
                  avatarUrl,
                  displayName.isNotEmpty ? displayName : username,
                  theme,
                ),
                const SizedBox(height: 20),
                _buildStatsRow(
                  context,
                  influenceScore,
                  influencePercentile,
                  intellectScore,
                  intellectPercentile,
                  scoreStats,
                  scoreHistory,
                  l10n,
                  theme,
                ),
                const SizedBox(height: 16),
                _buildBadgeRow(
                  context,
                  intellectPercentile,
                  tpBalance,
                  strikeCount,
                  l10n,
                  theme,
                ),
                const SizedBox(height: 24),
                Column(
                  children: [
                    if (displayName.isNotEmpty)
                      Text(
                        displayName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    if (displayName.isNotEmpty) const SizedBox(height: 4),
                    Text(
                      '@$username',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (bio.isNotEmpty) const SizedBox(height: 12),
                    if (bio.isNotEmpty)
                      Text(
                        bio,
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    if (location.isNotEmpty) const SizedBox(height: 8),
                    if (location.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            location,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    if (websiteUrl.isNotEmpty) const SizedBox(height: 8),
                    if (websiteUrl.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.link_outlined,
                            size: 16,
                            color: RengaColors.accent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              websiteUrl,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: RengaColors.accent,
                                decoration: TextDecoration.underline,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                if (isOwnProfile)
                  FilledButton.icon(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useRootNavigator: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (_) => ProfileEditSheet(userId: userId, profile: profile),
                    ),
                    icon: const Icon(Icons.edit),
                    label: Text(l10n.profileEditProfileButton),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _handleStartConversation(context, ref),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(l10n.messagesProfileMessageButton),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarSection(BuildContext context, String? avatarUrl, String fallbackName, ThemeData theme) {
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    return Column(
      children: [
        GestureDetector(
          onTap: hasAvatar
              ? () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FullscreenMediaViewer(imageUrls: [avatarUrl]),
                    ),
                  )
              : null,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RengaColors.accent.withValues(alpha: 0.1),
              border: Border.all(
                color: RengaColors.accent.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: hasAvatar
                ? ClipOval(
                    child: Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildInitialAvatar(fallbackName, theme),
                    ),
                  )
                : _buildInitialAvatar(fallbackName, theme),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialAvatar(String name, ThemeData theme) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: CircleAvatar(
        radius: 50,
        backgroundColor: RengaColors.accent.withValues(alpha: 0.2),
        child: Text(
          initial,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: RengaColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    dynamic influenceScore,
    dynamic influencePercentile,
    dynamic intellectScore,
    dynamic intellectPercentile,
    Map<String, dynamic>? scoreStats,
    List<Map<String, dynamic>> scoreHistory,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final influencePercentileNum =
        influencePercentile is num ? influencePercentile : num.tryParse('$influencePercentile') ?? 0;
    final intellectPercentileNum = intellectPercentile is num ? intellectPercentile : null;

    // design/system.md 2章「平均値・日次推移」。score_stats(全ユーザー平均のキャッシュ)との差分。
    final avgIntellectIq = (scoreStats?['avg_intellect_iq'] as num?)?.toDouble();
    final ownIq = intellectIqScore(intellectPercentileNum);
    final intellectVsAverageText = (avgIntellectIq != null && ownIq != null)
        ? l10n.profileScoreVsAverage(formatSignedDiff(ownIq - avgIntellectIq))
        : null;

    final avgInfluencePercentile = (scoreStats?['avg_influence_percentile'] as num?)?.toDouble();
    // パーセンタイルは値が小さいほど上位のため、「平均 - 自分」が正なら平均より上位。
    final influenceVsAverageText = avgInfluencePercentile != null
        ? l10n.profileScoreVsAverage(
            formatSignedDiff(avgInfluencePercentile - influencePercentileNum),
          )
        : null;

    // design/system.md 2章「日次推移」。直近のuser_score_historyスナップショットとの比較（前日比）。
    final latestHistory = scoreHistory.isNotEmpty ? scoreHistory.last : null;
    final previousInfluencePercentile = (latestHistory?['influence_percentile'] as num?)?.toDouble();
    final influenceDayOverDayText = previousInfluencePercentile != null
        ? l10n.profileScoreDayOverDay(
            formatSignedDiff(previousInfluencePercentile - influencePercentileNum),
          )
        : null;

    final influenceHistoryPoints = [
      for (final row in scoreHistory)
        ScoreHistoryPoint(
          date: DateTime.parse('${row['snapshot_date']}'),
          value: ((row['influence_percentile'] as num?)?.toDouble() ?? 0) / 100 * 10,
        ),
    ];
    final intellectHistoryPoints = [
      for (final row in scoreHistory)
        ScoreHistoryPoint(
          date: DateTime.parse('${row['snapshot_date']}'),
          value: intellectIqScore((row['intellect_percentile'] as num?))?.toDouble() ?? 100,
        ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatItem(
          label: l10n.profileScoreInfluence,
          score: _formatScoreOutOfTen(influencePercentile),
          percentile: '$influencePercentile%',
          vsAverageText: influenceVsAverageText,
          dayOverDayText: influenceDayOverDayText,
          theme: theme,
          accentColor: RengaColors.influence,
          onTap: () => showScoreHistorySheet(
            context,
            title: l10n.profileScoreHistoryTitle(l10n.profileScoreInfluence),
            points: influenceHistoryPoints,
            average: (avgInfluencePercentile ?? 50) / 100 * 10,
            color: RengaColors.influence,
            valueFormatter: (value) => value.toStringAsFixed(1),
          ),
          onInfoTap: () => showInfoBottomSheet(
            context,
            icon: Icons.trending_up,
            color: RengaColors.influence,
            title: l10n.profileScoreInfluence,
            description: 'Influenceは投稿の拡散力・エンゲージメント（いいね・リポスト・コメント）から'
                '算出される影響力スコアです。パーセンタイルは全ユーザー内での相対順位を表します。',
          ),
        ),
        Container(
          width: 1,
          height: 60,
          color: theme.colorScheme.outline,
        ),
        _buildStatItem(
          label: l10n.profileScoreIntellect,
          score: _formatIq(intellectPercentile),
          percentile: '$intellectPercentile%',
          vsAverageText: intellectVsAverageText,
          dayOverDayText: null,
          theme: theme,
          accentColor: RengaColors.intellect,
          onTap: () => showScoreHistorySheet(
            context,
            title: l10n.profileScoreHistoryTitle(l10n.profileScoreIntellect),
            points: intellectHistoryPoints,
            average: avgIntellectIq ?? 100,
            color: RengaColors.intellect,
            valueFormatter: (value) => value.round().toString(),
          ),
          onInfoTap: () => showInfoBottomSheet(
            context,
            icon: Icons.psychology,
            color: RengaColors.intellect,
            title: l10n.profileScoreIntellect,
            description: 'Intellectは投稿・クイズ正答などから算出される知的専門性スコアをIQスケール'
                '（平均100・標準偏差15）に換算した数値です。上位パーセンタイルに応じてバッジが'
                '付与されます（design/product.md 3.3節）。',
          ),
        ),
      ],
    );
  }

  /// パーセンタイル(0-100)を0.0〜10.0・小数第1位のスコア表示に正規化する。
  String _formatScoreOutOfTen(dynamic percentile) {
    final value = percentile is num ? percentile : num.tryParse('$percentile') ?? 0;
    return ((value / 100) * 10).toStringAsFixed(1);
  }

  /// Intellectパーセンタイルを[intellectIqScore]でIQスケールに変換した表示文字列。
  String _formatIq(dynamic percentile) {
    final value = percentile is num ? percentile : num.tryParse('$percentile');
    final iq = intellectIqScore(value);
    return iq?.toString() ?? '--';
  }

  /// design/product.md 3.10節「平均値との比較・前日比の表示」「推移グラフ」。
  /// タップ（[onTap]）で `user_score_history` の推移グラフを開き、ラベル横の infoアイコン
  /// （[onInfoTap]）で従来通りの算出方法の説明ボトムシートを開く。
  Widget _buildStatItem({
    required String label,
    required String score,
    required String percentile,
    String? vsAverageText,
    String? dayOverDayText,
    required ThemeData theme,
    required Color accentColor,
    required VoidCallback onTap,
    required VoidCallback onInfoTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Text(
              score,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                GestureDetector(
                  onTap: onInfoTap,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      Icons.info_outline,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              percentile,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (vsAverageText != null)
              Text(
                vsAverageText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (dayOverDayText != null)
              Text(
                dayOverDayText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeRow(
    BuildContext context,
    num? intellectPercentile,
    dynamic tpBalance,
    int strikeCount,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final badges = <Widget>[
      IntellectBadge(percentile: intellectPercentile),
    ];

    final tpBalanceNum = tpBalance is num ? tpBalance : 0;
    badges.add(
      GestureDetector(
        onTap: () => showInfoBottomSheet(
          context,
          icon: Icons.toll,
          color: RengaColors.accent,
          title: 'TP（トークンポイント）',
          description: 'TPはステーキング投稿などアプリ内の各種アクションで使用するポイントです。'
              'クイズ通過や日々の活動で獲得でき、ステーキング・ツイートで賭けることができます'
              '（design/product.md 3.4節）。',
        ),
        child: Chip(
          label: Text('${tpBalanceNum.toStringAsFixed(0)} TP'),
          labelStyle: theme.textTheme.bodySmall,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          padding: const EdgeInsets.symmetric(vertical: 0),
          backgroundColor: RengaColors.accent.withValues(alpha: 0.1),
          side: BorderSide(color: RengaColors.accent.withValues(alpha: 0.3)),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );

    if (strikeCount > 0) {
      badges.add(
        Chip(
          label: Text('${l10n.profileStrikeCountLabel}: $strikeCount'),
          labelStyle: theme.textTheme.bodySmall,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          padding: const EdgeInsets.symmetric(vertical: 0),
          backgroundColor: Colors.red.withValues(alpha: 0.1),
          side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: badges,
    );
  }
}
