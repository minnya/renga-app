import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import 'battle.dart';
import 'battle_controller.dart';

/// design/product.md 4章「Battle Tab」の詳細画面。
///
/// 対象投稿 vs 挑戦投稿を並べて表示し、観客ベットUI（challenger/defenderへの
/// TPベット）を提供する。精算ロジック（design/system.md 12章のEdge Function）は
/// 未実装のため、ベットは `battle_bets` へのinsertのみで完結する。
class BattleDetailPage extends ConsumerWidget {
  const BattleDetailPage({super.key, required this.battleId});

  final String battleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final battleAsync = ref.watch(battleDetailProvider(battleId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.battleDetailAppBarTitle)),
      body: battleAsync.when(
        data: (battle) => _BattleDetailBody(battle: battle),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(l10n.battleListLoadError('$error'))),
        ),
      ),
    );
  }
}

class _BattleDetailBody extends ConsumerWidget {
  const _BattleDetailBody({required this.battle});

  final Battle battle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.watch(currentUserProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.battleDetailIntro,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Chip(label: Text(battle.isActive ? l10n.battleTabActive : l10n.battleTabResolved)),
            const SizedBox(width: 8),
            Text(l10n.battleResolvesAtLabel(_formatDateTime(battle.resolvesAt))),
          ],
        ),
        if (!battle.isActive && battle.winner != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.battleWinnerLabel(
              battle.winner == 'challenger' ? l10n.battleChallengerFallback : l10n.battleWinnerDefender,
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 16),
        _PostCompareCard(
          label: l10n.battleTargetPostLabel,
          username: battle.targetPostAuthorUsername,
          body: battle.targetPostBody,
          stakeTp: battle.defenderStakeTp,
          isChallenger: false,
        ),
        const SizedBox(height: 8),
        const Center(child: Icon(Icons.compare_arrows, size: 28)),
        const SizedBox(height: 8),
        _PostCompareCard(
          label: l10n.battleChallengerPostLabel,
          username: battle.challengerPostAuthorUsername,
          body: battle.challengerPostBody,
          stakeTp: battle.challengerStakeTp,
          isChallenger: true,
        ),
        const SizedBox(height: 24),
        if (battle.isActive && currentUser != null)
          _BetForm(battleId: battle.id)
        else if (battle.isActive)
          Center(child: Text(l10n.battleLoginRequiredForBet)),
      ],
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

class _PostCompareCard extends StatelessWidget {
  const _PostCompareCard({
    required this.label,
    required this.username,
    required this.body,
    required this.stakeTp,
    this.isChallenger = false,
  });

  final String label;
  final String? username;
  final String? body;
  final num stakeTp;
  final bool isChallenger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Use intellect color for target (defender) on the left, influence for challenger on the right
    final accentColor = isChallenger ? RengaColors.influence : RengaColors.intellect;

    // Create a subtle background and border using the accent color with low opacity
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = accentColor.withAlpha(100);
    final backgroundColor = accentColor.withAlpha(isDark ? 20 : 15);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: backgroundColor,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: accentColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      isChallenger ? l10n.battleRoleChallenger : l10n.battleRoleDefender,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                username ?? l10n.feedUnknownUser,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                body ?? l10n.battlePostNotFound,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.battleStakeTpLabel(stakeTp.toStringAsFixed(0)),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 観客ベットの入力フォーム。challenger/defenderの選択とTP額の入力のみを持つ土台実装。
class _BetForm extends ConsumerStatefulWidget {
  const _BetForm({required this.battleId});

  final String battleId;

  @override
  ConsumerState<_BetForm> createState() => _BetFormState();
}

class _BetFormState extends ConsumerState<_BetForm> {
  String _side = 'defender';
  final _amountController = TextEditingController(text: '10');
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final amount = num.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.battleBetInvalidAmount)),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(battleControllerProvider).placeBet(
            battleId: widget.battleId,
            userId: currentUser.id,
            side: _side,
            amountTp: amount,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.battleBetSuccess)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.battleBetError('$error'))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.battleAudienceBetTitle, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'defender', label: Text(l10n.battleSideDefender)),
                ButtonSegment(value: 'challenger', label: Text(l10n.battleSideChallenger)),
              ],
              selected: {_side},
              onSelectionChanged: (selection) => setState(() => _side = selection.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.battleBetAmountLabel),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? l10n.battleBetSubmitting : l10n.battleBetSubmitButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
