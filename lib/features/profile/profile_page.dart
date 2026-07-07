import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('プロフィールを表示するにはログインしてください'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/login'),
              child: const Text('ログイン画面へ'),
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
    setState(() => _saving = true);
    try {
      await ref.read(profileControllerProvider).updateProfile(
            userId: widget.userId,
            displayName: _displayNameController.text.trim(),
            bio: _bioController.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗しました: $e')),
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
    final profileAsync = ref.watch(profileProvider(widget.userId));

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Text('プロフィールの取得に失敗しました: $error'),
      ),
      data: (profile) {
        _initializeControllersIfNeeded(profile);

        final username = (profile['username'] as String?) ?? '';
        final influenceScore = profile['influence_score'];
        final influencePercentile = profile['influence_percentile'];
        final intellectScore = profile['intellect_score'];
        final intellectPercentile = profile['intellect_percentile'];
        final intellectBadgeLabel = _intellectBadgeLabel(intellectPercentile as num?);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('username', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(username, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            TextField(
              controller: _displayNameController,
              decoration: const InputDecoration(
                labelText: '表示名 (display name)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bioController,
              decoration: const InputDecoration(
                labelText: '自己紹介 (bio)',
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _handleSave,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
            const SizedBox(height: 32),
            Text('評価', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ScoreCard(
                    label: 'Influence',
                    score: influenceScore,
                    percentile: influencePercentile,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ScoreCard(
                    label: 'Intellect',
                    score: intellectScore,
                    percentile: intellectPercentile,
                    badgeLabel: intellectBadgeLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: _handleSignOut,
              child: const Text('ログアウト'),
            ),
          ],
        );
      },
    );
  }
}

/// design/product.md 4章「上位25%/5%知能バッジ」。値が小さいほど上位を表す前提。
/// パーセンタイル自動再計算バッチ（Phase3）が未実装のため、現状は全ユーザーで`0`のまま。
String? _intellectBadgeLabel(num? percentile) {
  if (percentile == null) return null;
  if (percentile <= 5) return '上位5%';
  if (percentile <= 25) return '上位25%';
  return null;
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.label,
    required this.score,
    required this.percentile,
    this.badgeLabel,
  });

  final String label;
  final dynamic score;
  final dynamic percentile;
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                if (badgeLabel != null) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(badgeLabel!, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text('$score', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('上位 $percentile%', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
