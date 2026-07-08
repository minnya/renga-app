import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';
import '../../l10n/gen/app_localizations.dart';
import '../feed/intellect_badge.dart';
import 'profile_controller.dart';

/// プロフィール表示・編集画面。
///
/// - 未ログイン時: ログイン画面へ誘導する案内を表示する。
/// - ログイン時: 自分の `profiles` 行を取得し、username（読み取り専用）、
///   display_name / bio（編集可能）、influence / intellect の2軸評価（読み取り専用）を表示する。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileAppBarTitle)),
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

class _SignedInProfileView extends ConsumerStatefulWidget {
  const _SignedInProfileView({required this.userId});

  final String userId;

  @override
  ConsumerState<_SignedInProfileView> createState() => _SignedInProfileViewState();
}

class _SignedInProfileViewState extends ConsumerState<_SignedInProfileView> {
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _editMode = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _initializeControllersIfNeeded(Map<String, dynamic> profile) {
    if (_initialized) return;
    _displayNameController.text = (profile['display_name'] as String?) ?? '';
    _bioController.text = (profile['bio'] as String?) ?? '';
    _initialized = true;
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(profileControllerProvider).updateProfile(
            userId: widget.userId,
            displayName: _displayNameController.text.trim(),
            bio: _bioController.text.trim(),
          );
      if (!mounted) return;
      setState(() => _editMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileSaveSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileSaveError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleSignOut() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider(widget.userId));
    final theme = Theme.of(context);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Text(l10n.profileLoadError('$error')),
      ),
      data: (profile) {
        _initializeControllersIfNeeded(profile);

        final avatarUrl = (profile['avatar_url'] as String?);
        final displayName = (profile['display_name'] as String?) ?? '';
        final username = (profile['username'] as String?) ?? '';
        final bio = (profile['bio'] as String?) ?? '';
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
                // Avatar section
                _buildAvatarSection(
                  avatarUrl,
                  displayName.isNotEmpty ? displayName : username,
                  theme,
                ),
                const SizedBox(height: 20),

                // Stats row (Instagram style)
                _buildStatsRow(
                  influenceScore,
                  influencePercentile,
                  intellectScore,
                  intellectPercentile,
                  l10n,
                  theme,
                ),
                const SizedBox(height: 16),

                // Badge row (IntellectBadge, TP, Strikes)
                _buildBadgeRow(
                  intellectPercentile,
                  tpBalance,
                  strikeCount,
                  l10n,
                  theme,
                ),
                const SizedBox(height: 24),

                // Username display
                if (!_editMode)
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
                    ],
                  ),

                const SizedBox(height: 24),

                // Edit mode
                if (_editMode) ...[
                  TextField(
                    controller: _displayNameController,
                    decoration: InputDecoration(
                      labelText: l10n.profileDisplayNameLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _bioController,
                    decoration: InputDecoration(
                      labelText: l10n.profileBioLabel,
                      border: const OutlineInputBorder(),
                    ),
                    minLines: 3,
                    maxLines: 6,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _handleSave,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(l10n.profileSaveButton),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _editMode = false),
                          child: Text(l10n.profileGoToLogin), // Reuse or use a cancel key
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => setState(() => _editMode = true),
                    icon: const Icon(Icons.edit),
                    label: Text(l10n.profileEditProfileButton),
                  ),
                ],

                const SizedBox(height: 24),

                // Sign out button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _handleSignOut,
                    child: Text(l10n.profileSignOutButton),
                  ),
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
          child: avatarUrl != null && avatarUrl.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildInitialAvatar(fallbackName, theme);
                    },
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
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
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
    final badges = <Widget>[];

    // Intellect badge
    badges.add(
      IntellectBadge(percentile: intellectPercentile),
    );

    // TP Balance chip
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

    // Strike count badge (only if > 0)
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
