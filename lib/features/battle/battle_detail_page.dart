import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
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
    final battleAsync = ref.watch(battleDetailProvider(battleId));

    return Scaffold(
      appBar: AppBar(title: const Text('バトル詳細')),
      body: battleAsync.when(
        data: (battle) => _BattleDetailBody(battle: battle),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text('バトルの取得に失敗しました: $error')),
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
    final currentUser = ref.watch(currentUserProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Chip(label: Text(battle.isActive ? '進行中' : '終了')),
            const SizedBox(width: 8),
            Text('決着予定: ${_formatDateTime(battle.resolvesAt)}'),
          ],
        ),
        if (!battle.isActive && battle.winner != null) ...[
          const SizedBox(height: 8),
          Text(
            '勝者: ${battle.winner == 'challenger' ? '挑戦者' : '対象投稿者'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 16),
        _PostCompareCard(
          label: '対象投稿（防衛側）',
          username: battle.targetPostAuthorUsername,
          body: battle.targetPostBody,
          stakeTp: battle.defenderStakeTp,
        ),
        const SizedBox(height: 8),
        const Center(child: Icon(Icons.compare_arrows, size: 28)),
        const SizedBox(height: 8),
        _PostCompareCard(
          label: '挑戦投稿（挑戦側）',
          username: battle.challengerPostAuthorUsername,
          body: battle.challengerPostBody,
          stakeTp: battle.challengerStakeTp,
        ),
        const SizedBox(height: 24),
        if (battle.isActive && currentUser != null)
          _BetForm(battleId: battle.id)
        else if (battle.isActive)
          const Center(child: Text('ベットにはログインが必要です')),
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
  });

  final String label;
  final String? username;
  final String? body;
  final num stakeTp;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(username ?? '不明なユーザー', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(body ?? '（投稿が見つかりません）'),
            const SizedBox(height: 8),
            Text('ステークTP: ${stakeTp.toStringAsFixed(0)}'),
          ],
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
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final amount = num.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正しいTP額を入力してください')),
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
        const SnackBar(content: Text('ベットしました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ベットに失敗しました: $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('観客ベット', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'defender', label: Text('対象投稿側')),
                ButtonSegment(value: 'challenger', label: Text('挑戦側')),
              ],
              selected: {_side},
              onSelectionChanged: (selection) => setState(() => _side = selection.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'ベットTP額'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? '送信中...' : 'ベットする'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
