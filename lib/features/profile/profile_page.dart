import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../feed/intellect_badge.dart';
import 'profile_controller.dart';
import 'profile_edit_sheet.dart';

/// プロフィール表示・編集画面。
///
/// - 未ログイン時: ログイン画面へ誘導する案内を表示する。
/// - ログイン時: 自分の `profiles` 行を取得し、常に読み取り専用ビューを表示する。
///   編集は「編集」ボタンから開く [ProfileEditSheet]（ボトムシート）で行う
///   （design/product.md 3.10節）。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileAppBarTitle),
        // design/product.md 3.11節「Settings画面」。Profile画面の歯車アイコンから遷移する。
        actions: [
          if (currentUser != null)
            IconButton(
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: currentUser == null
          ? _SignedOutView()
          : _SignedInProfileView(userId: currentUser.id),
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
  const _SignedInProfileView({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider(userId));
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
                  avatarUrl,
                  displayName.isNotEmpty ? displayName : username,
                  theme,
                ),
                const SizedBox(height: 20),
                _buildStatsRow(
                  influenceScore,
                  influencePercentile,
                  intellectScore,
                  intellectPercentile,
                  l10n,
                  theme,
                ),
                const SizedBox(height: 16),
                _buildBadgeRow(
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
                FilledButton.icon(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (_) => ProfileEditSheet(userId: userId, profile: profile),
                  ),
                  icon: const Icon(Icons.edit),
                  label: Text(l10n.profileEditProfileButton),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarSection(String? avatarUrl, String fallbackName, ThemeData theme) {
    return Column(
      children: [
        Container(
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
          child: (avatarUrl != null && avatarUrl.isNotEmpty)
              ? ClipOval(
                  child: Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildInitialAvatar(fallbackName, theme),
                  ),
                )
              : _buildInitialAvatar(fallbackName, theme),
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
    dynamic influenceScore,
    dynamic influencePercentile,
    dynamic intellectScore,
    dynamic intellectPercentile,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatItem(
          label: l10n.profileScoreInfluence,
          score: '$influenceScore',
          percentile: '$influencePercentile%',
          theme: theme,
          accentColor: RengaColors.influence,
        ),
        Container(
          width: 1,
          height: 60,
          color: theme.colorScheme.outline,
        ),
        _buildStatItem(
          label: l10n.profileScoreIntellect,
          score: '$intellectScore',
          percentile: '$intellectPercentile%',
          theme: theme,
          accentColor: RengaColors.intellect,
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required String label,
    required String score,
    required String percentile,
    required ThemeData theme,
    required Color accentColor,
  }) {
    return Expanded(
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
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            percentile,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeRow(
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
      Chip(
        label: Text('${tpBalanceNum.toStringAsFixed(0)} TP'),
        labelStyle: theme.textTheme.bodySmall,
        backgroundColor: RengaColors.accent.withValues(alpha: 0.1),
        side: BorderSide(color: RengaColors.accent.withValues(alpha: 0.3)),
        visualDensity: VisualDensity.compact,
      ),
    );

    if (strikeCount > 0) {
      badges.add(
        Chip(
          label: Text('${l10n.profileStrikeCountLabel}: $strikeCount'),
          labelStyle: theme.textTheme.bodySmall,
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
