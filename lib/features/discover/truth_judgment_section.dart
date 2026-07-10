import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_state.dart';
import '../profile/profile_controller.dart';
import 'discover_controller.dart';
import 'truth_judgment.dart';

/// design/product.md 3.4節「反応手段2：真偽投票（投票権チケット消費、リクエスト起点）」。
///
/// Discoverコンテキストの投稿1件につき表示する真偽審判UI。常時表示ではなく
/// オプトイン型で、リクエストが起票されている投稿にのみ投票UI・結果が現れる。
///
/// - リクエスト未起票: `Create`権限（上位25%以上）保持者にのみ活性の「真偽審判リクエスト」ボタンを
///   表示する。それ以外のユーザーには非活性状態で表示し、タップ時に理由を説明するダイアログを出す。
/// - 投票中（`voting`）: 投票資格（上位25%かつ投稿者本人と同格以上、自己投票不可、未投票）を
///   満たすユーザーにのみ「本当」「嘘」への投票ボタン（チケット1枚消費）を表示する。
/// - **ブラインド投票フェーズ（3.4.2節）**: 自分がまだ投票していない間は、投票比率を一切見せず
///   「現在N人投票中」という総数のみ表示する（モザイク）。自分の投票が成立した瞬間、または
///   `resolved`/`invalid`確定後に、2階建てインテリジェンス・メーター（3.4.4節）としてアンロックする。
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
          // リクエスト未起票: ボタン自体は常時表示し、Create権限（上位25%以上）を
          // 持たないユーザーには非活性状態で表示する。タップ時は理由を説明するダイアログを出す。
          final canRequest = isTopTier && currentUser != null;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: canRequest
                  ? () => _requestJudgment(context, ref)
                  : () => _showIneligibleDialog(context, currentUser == null),
              style: canRequest
                  ? null
                  : OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).disabledColor,
                      side: BorderSide(color: Theme.of(context).disabledColor),
                    ),
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

  Future<void> _showIneligibleDialog(BuildContext context, bool notLoggedIn) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('真偽審判リクエストはできません'),
        content: Text(
          notLoggedIn
              ? 'ログインすると利用できる機能です。'
              : '真偽審判リクエストは、知能スコア上位25%以上のCreate権限保持者のみが起票できます。'
                    'クイズに挑戦してIntellect Scoreを上げると、Create権限を獲得できます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
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
  bool _isSubmitting = false;

  Future<void> _vote(bool verdict) async {
    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(discoverControllerProvider)
          .castTruthVote(
            requestId: widget.request.id,
            postId: widget.request.postId,
            verdict: verdict,
          );
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showTicketShop() async {
    await showTicketShopSheet(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final currentUser = ref.watch(currentUserProvider);
    final myVoteAsync = ref.watch(myTruthVoteProvider(request.id));
    final myProfileAsync = currentUser == null
        ? const AsyncValue<Map<String, dynamic>?>.data(null)
        : ref.watch(profileProvider(currentUser.id));

    final myVote = myVoteAsync.value;
    final isAuthor = currentUser != null && currentUser.id == widget.postAuthorId;
    final myPercentile = myProfileAsync.value?['intellect_percentile'] as num?;
    final isEligible = widget.isTopTier &&
        !isAuthor &&
        currentUser != null &&
        myPercentile != null &&
        myPercentile <= request.authorIntellectPercentileSnapshot;

    // design/product.md 3.4.2節「処刑フェーズ」。確定済み、または自分が投票済みの場合のみ
    // 2階建てメーターをアンロックする。それ以外（自分が未投票かつ投票中）はブラインドのまま。
    final isUnlocked = request.isResolved || request.isInvalid || myVote != null;

    final statusChip = request.isResolved
        ? Chip(
            label: Text(request.resolvedVerdict == true ? '判定確定: 真' : '判定確定: 偽'),
            visualDensity: VisualDensity.compact,
          )
        : request.isInvalid
        ? const Chip(
            label: Text('無効・返還（クォーラム未達）'),
            visualDensity: VisualDensity.compact,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (statusChip != null) ...[statusChip, const SizedBox(height: 4)],
        if (isUnlocked)
          _IntelligenceMeter(requestId: request.id)
        else
          _BlindMeter(requestId: request.id),
        if (request.isVoting) ...[
          const SizedBox(height: 4),
          if (myVote != null)
            Text(
              '投票済み: ${myVote.verdict ? "本当" : "嘘"}',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (isEligible)
            _VoteControls(
              isSubmitting: _isSubmitting,
              onVote: _vote,
              onOpenShop: _showTicketShop,
            ),
        ],
      ],
    );
  }
}

/// design/product.md 3.4.2節「ブラインド投票フェーズ」。投票比率は一切見せず、
/// 総票数（総消費チケット数）のみを表示する。
class _BlindMeter extends ConsumerWidget {
  const _BlindMeter({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votesAsync = ref.watch(allTruthVotesProvider(requestId));
    final total = votesAsync.value?.length ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.blur_on, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '真偽判定 審議中 — 現在$total人が投票中',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// design/product.md 3.4.4節「2階建てインテリジェンス・メーター」。Top5%/Top25%それぞれの
/// 「黒（嘘）」比率をバーで独立表示する。アンロック後（自分の投票完了後 or 確定後）にのみ表示する。
class _IntelligenceMeter extends ConsumerWidget {
  const _IntelligenceMeter({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votesAsync = ref.watch(allTruthVotesProvider(requestId));
    final votes = votesAsync.value ?? const [];

    final top5Votes = votes.where((v) => v.isTop5).toList();
    final top25Votes = votes.where((v) => !v.isTop5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MeterRow(label: 'Top 5% (Masters)', color: Colors.purple, votes: top5Votes),
        const SizedBox(height: 4),
        _MeterRow(label: 'Top 25% (Seniors)', color: Colors.blue, votes: top25Votes),
      ],
    );
  }
}

class _MeterRow extends StatelessWidget {
  const _MeterRow({required this.label, required this.color, required this.votes});

  final String label;
  final Color color;
  final List<TruthVote> votes;

  @override
  Widget build(BuildContext context) {
    final total = votes.length;
    final falseCount = votes.where((v) => !v.verdict).length;
    final falseRatio = total == 0 ? 0.0 : falseCount / total;

    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : falseRatio,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          total == 0 ? '票なし' : '黒 ${(falseRatio * 100).round()}%（$total票）',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// 投票権チケットを1枚消費して「本当」「嘘」に投票するボタン列。チケット残高が0枚の場合は
/// ショップへの導線ボタンに差し替える（design/product.md 3.4.3節）。
class _VoteControls extends ConsumerWidget {
  const _VoteControls({required this.isSubmitting, required this.onVote, required this.onOpenShop});

  final bool isSubmitting;
  final void Function(bool verdict) onVote;
  final VoidCallback onOpenShop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketCountAsync = ref.watch(ticketCountProvider);
    final ticketCount = ticketCountAsync.value ?? 0;

    if (ticketCount <= 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: OutlinedButton.icon(
          onPressed: onOpenShop,
          icon: const Icon(Icons.confirmation_number_outlined, size: 16),
          label: const Text('投票権チケットを購入する'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text('保有チケット: $ticketCount枚', style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          FilledButton(
            onPressed: isSubmitting ? null : () => onVote(true),
            child: const Text('本当'),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: isSubmitting ? null : () => onVote(false),
            child: const Text('嘘'),
          ),
        ],
      ),
    );
  }
}

/// design/product.md 3.4.3節「投票権チケット」エコノミー。一般ユーザー向けのチケット購入
/// ボトムシート（1枚=100TP）。
Future<void> showTicketShopSheet(BuildContext context, WidgetRef ref) async {
  final counts = [1, 5, 10];
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('投票権チケットを購入', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final count in counts)
              ListTile(
                leading: const Icon(Icons.confirmation_number_outlined),
                title: Text('$count枚（${count * 100} TP）'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(discoverControllerProvider).purchaseTickets(ticketCount: count);
                    messenger.showSnackBar(SnackBar(content: Text('$count枚購入しました')));
                  } on PostgrestException catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(e.message)));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
              ),
          ],
        ),
      );
    },
  );
}
