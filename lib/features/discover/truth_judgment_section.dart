import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_state.dart';
import '../profile/profile_controller.dart';
import 'discover_controller.dart';
import 'truth_judgment.dart';

/// design/product.md 3.4節「反応手段2：真偽投票（TPベット、リクエスト起点）」。
///
/// Discoverコンテキストの投稿1件につき表示する真偽審判UI。常時表示ではなく
/// オプトイン型で、リクエストが起票されている投稿にのみ投票UI・結果が現れる。
///
/// - リクエスト未起票: `Create`権限（上位25%以上）保持者にのみ「真偽審判リクエスト」ボタンを表示。
/// - 投票中（`voting`）: 投票資格（上位25%かつ投稿者本人と同格以上、自己投票不可、未投票）を
///   満たすユーザーにのみ「本当」「嘘」のボタン＋TPステーク入力を表示。既に投票済みなら
///   その投票内容を読み取り専用表示する。
/// - `resolved`/`invalid`: 確定結果（真/偽/無効・返還）を表示する。
/// - 集計件数（真/偽の票数）は資格の有無に関わらず常に表示する（一般ユーザーも閲覧可）。
class TruthJudgmentSection extends ConsumerWidget {
  const TruthJudgmentSection({super.key, required this.postId, required this.postAuthorId});

  final String postId;
  final String postAuthorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestAsync = ref.watch(truthJudgmentRequestProvider(postId));
    final isTopTierAsync = ref.watch(isTopIntellectTierProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isTopTier = isTopTierAsync.value ?? false;

    return requestAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (request) {
        if (request == null) {
          // リクエスト未起票: Create権限保持者にのみリクエストボタンを表示する。
          if (!isTopTier || currentUser == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => _requestJudgment(context, ref),
              icon: const Icon(Icons.gavel_outlined, size: 16),
              label: const Text('真偽審判リクエスト'),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _RequestBody(
            request: request,
            postAuthorId: postAuthorId,
            isTopTier: isTopTier,
          ),
        );
      },
    );
  }

  Future<void> _requestJudgment(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(discoverControllerProvider).requestTruthJudgment(postId: postId);
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _RequestBody extends ConsumerStatefulWidget {
  const _RequestBody({
    required this.request,
    required this.postAuthorId,
    required this.isTopTier,
  });

  final TruthJudgmentRequest request;
  final String postAuthorId;
  final bool isTopTier;

  @override
  ConsumerState<_RequestBody> createState() => _RequestBodyState();
}

class _RequestBodyState extends ConsumerState<_RequestBody> {
  final _stakeController = TextEditingController(text: '10');
  bool _isSubmitting = false;

  @override
  void dispose() {
    _stakeController.dispose();
    super.dispose();
  }

  Future<void> _vote(bool verdict) async {
    final stake = num.tryParse(_stakeController.text.trim());
    if (stake == null || stake <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('賭けるTPは1以上を指定してください')));
      return;
    }

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(discoverControllerProvider)
          .castTruthVote(
            requestId: widget.request.id,
            postId: widget.request.postId,
            verdict: verdict,
            stakedTp: stake,
          );
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final currentUser = ref.watch(currentUserProvider);
    final myVoteAsync = ref.watch(myTruthVoteProvider(request.id));
    final myProfileAsync = currentUser == null
        ? const AsyncValue<Map<String, dynamic>?>.data(null)
        : ref.watch(profileProvider(currentUser.id));

    final countsLabel = Text(
      '本当 ${request.trueVoteCount} / 嘘 ${request.falseVoteCount}',
      style: Theme.of(context).textTheme.bodySmall,
    );

    if (request.isResolved) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(
            label: Text(request.resolvedVerdict == true ? '判定確定: 真' : '判定確定: 偽'),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 4),
          countsLabel,
        ],
      );
    }

    if (request.isInvalid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Chip(
            label: Text('無効・返還（クォーラム未達）'),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: 4),
          countsLabel,
        ],
      );
    }

    // status == 'voting'
    final myVote = myVoteAsync.value;
    final isAuthor = currentUser != null && currentUser.id == widget.postAuthorId;
    final myPercentile = myProfileAsync.value?['intellect_percentile'] as num?;
    final isEligible = widget.isTopTier &&
        !isAuthor &&
        currentUser != null &&
        myPercentile != null &&
        myPercentile <= request.authorIntellectPercentileSnapshot;

    if (myVote != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          countsLabel,
          const SizedBox(height: 4),
          Text(
            '投票済み: ${myVote.verdict ? "本当" : "嘘"}（${myVote.stakedTp} TP）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    if (!isEligible) {
      return countsLabel;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        countsLabel,
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _stakeController,
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                decoration: const InputDecoration(
                  labelText: '賭けるTP',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isSubmitting ? null : () => _vote(true),
              child: const Text('本当'),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: _isSubmitting ? null : () => _vote(false),
              child: const Text('嘘'),
            ),
          ],
        ),
      ],
    );
  }
}
