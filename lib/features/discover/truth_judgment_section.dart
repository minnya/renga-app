import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_state.dart';
import '../profile/profile_controller.dart';
import 'discover_controller.dart';
import 'truth_judgment.dart';

/// design/product.md 3.4節「反応手段2：真偽投票（投票権チケット消費、リクエスト起点）」。
///
/// Feed/Discoverいずれのコンテキストの投稿にも表示する真偽審判UI。常時表示ではなく
/// オプトイン型で、リクエストが起票されている投稿にのみ投票UI・結果が現れる。
///
/// - リクエスト未起票: `Create`権限（上位25%以上）保持者にのみ活性の「真偽審判リクエスト」ボタンを
///   表示する。それ以外のユーザーには非活性状態で表示し、タップ時に理由を説明するダイアログを出す。
/// - 投票中（`voting`）: 投票資格（上位25%かつ投稿者本人と同格以上、自己投票不可、未投票）を
///   満たすユーザーにのみ「本当」「嘘」への投票ボタン（チケット1枚消費）を表示する。起票者本人は
///   投稿者本人以上の知能階層チェックを免除され、常に自分が起票した投票に参加できる。
/// - **ブラインド投票フェーズ（3.4.2節）**: 自分がまだ投票していない間は、投票比率を一切見せず
///   「審議投票中」というステータス・締切までの残り時間・総票数のみ表示する（モザイク）。
///   自分の投票が成立した瞬間、または`resolved`/`invalid`確定後に、真/偽の内訳を1本のバーに
///   色分けして表示するインテリジェンス・メーター（3.4.4節）としてアンロックする。
/// design/product.md 3.12節「アクションバーの表示形式」。いいね・コメント・リポスト・
/// 真偽審判・シェアの順で1列に並ぶアクションバー内に配置する、アイコンのみのトリガー
/// ボタン（3.4節）。
///
/// - リクエスト未起票: `Create`権限（上位25%以上）保持者にのみ活性のアイコンを表示する。
///   タップすると権限の有無に関わらずまず説明・確認ダイアログを開く。
/// - 投票中/確定済み: 審議が進行中であることを示すアイコン（塗りつぶし表示）に切り替える。
///   タップすると現在のステータスのみを表示する読み取り専用ダイアログを開く
///   （投票そのものは[TruthJudgmentBody]の専用UIで行う）。
class TruthJudgmentIcon extends ConsumerWidget {
  const TruthJudgmentIcon({super.key, required this.postId});

  final String postId;

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
          final canRequest = isTopTier && currentUser != null;
          return GestureDetector(
            onTap: () => _showJudgmentRequestDialog(context, ref, canRequest, currentUser == null),
            child: Icon(
              Icons.gavel_outlined,
              size: 20,
              color: canRequest ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).disabledColor,
            ),
          );
        }

        return GestureDetector(
          onTap: () => _showJudgmentStatusDialog(context, request),
          child: Icon(
            Icons.gavel,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }

  /// design/product.md 3.4節。アイコンタップ時、権限の有無に関わらずまず真偽審判リクエストの
  /// 説明ダイアログを開く。Create権限保持者にのみ実行ボタンを表示し、それ以外は理由のみ表示する。
  Future<void> _showJudgmentRequestDialog(
    BuildContext context,
    WidgetRef ref,
    bool canRequest,
    bool notLoggedIn,
  ) async {
    const explanation =
        '真偽審判リクエストは、投稿の真偽を上位ユーザーの投票にかける機能です。'
        'リクエストすると、投稿者本人と同格以上の知能階層のユーザーが「本当」「嘘」に投票し、'
        '24時間後に多数決で真偽が確定します。';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('真偽審判リクエスト'),
        content: Text(
          canRequest
              ? explanation
              : notLoggedIn
                  ? '$explanation\n\nログインすると利用できる機能です。'
                  : '$explanation\n\n起票は、知能スコア上位25%以上のCreate権限保持者のみが行えます。'
                        'クイズに挑戦してIntellect Scoreを上げると、Create権限を獲得できます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('閉じる'),
          ),
          if (canRequest)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _requestJudgment(context, ref);
              },
              child: const Text('リクエストする'),
            ),
        ],
      ),
    );
  }

  Future<void> _showJudgmentStatusDialog(BuildContext context, TruthJudgmentRequest request) async {
    final statusText = request.isResolved
        ? '判定確定: ${request.resolvedVerdict == true ? "真" : "偽"}'
        : request.isInvalid
        ? '無効・返還（クォーラム未達）'
        : '審議投票中（締切まで残り時間はメーターを参照）';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('真偽審判リクエスト'),
        content: Text('この投稿は真偽審判の対象になっています。\n\n$statusText'),
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

/// design/product.md 3.4節。真偽審判リクエストが起票されている投稿にのみ表示する、
/// 投票用のブラインド/インテリジェンス・メーターと投票ボタン。アクションバー内の
/// [TruthJudgmentIcon]とは別に、アクションバーの下に表示する。
class TruthJudgmentBody extends ConsumerWidget {
  const TruthJudgmentBody({super.key, required this.postId, required this.postAuthorId});

  final String postId;
  final String postAuthorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestAsync = ref.watch(truthJudgmentRequestProvider(postId));
    final isTopTierAsync = ref.watch(isTopIntellectTierProvider);
    final isTopTier = isTopTierAsync.value ?? false;

    return requestAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (request) {
        if (request == null) return const SizedBox.shrink();

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
    final isRequester = currentUser != null && currentUser.id == request.requestedBy;
    final myPercentile = myProfileAsync.value?['intellect_percentile'] as num?;
    // design/product.md 3.4節。起票者本人は「投稿者本人と同格以上」の階層チェックを免除される
    // （審議ボタンを押した本人も自分が起票した投票に参加できる）。
    final isEligible = widget.isTopTier &&
        !isAuthor &&
        currentUser != null &&
        (isRequester ||
            (myPercentile != null && myPercentile <= request.authorIntellectPercentileSnapshot));

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
          _BlindMeter(requestId: request.id, closesAt: request.closesAt),
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
/// 「審議投票中」というステータスと、締切までの残り時間、総票数のみを表示する。
class _BlindMeter extends ConsumerStatefulWidget {
  const _BlindMeter({required this.requestId, required this.closesAt});

  final String requestId;
  final DateTime closesAt;

  @override
  ConsumerState<_BlindMeter> createState() => _BlindMeterState();
}

class _BlindMeterState extends ConsumerState<_BlindMeter> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 締切までの残り時間表示を更新するため、30秒おきに再描画する。
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatRemaining(Duration d) {
    if (d.isNegative) return 'まもなく締切';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '締切まであと$hours時間$minutes分';
    return '締切まであと$minutes分';
  }

  @override
  Widget build(BuildContext context) {
    final votesAsync = ref.watch(allTruthVotesProvider(widget.requestId));
    final total = votesAsync.value?.length ?? 0;
    final remaining = widget.closesAt.difference(DateTime.now());

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('審議投票中 — 現在$total人が投票中', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  _formatRemaining(remaining),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// design/product.md 3.4.4節「インテリジェンス・メーター」。締切後（または自分の投票完了後）に
/// アンロックされる、真/偽の内訳を1本のバーに色分けして表示するメーター。件数・比率・真偽の
/// ラベルはすべてバー内にオーバーレイ表示する。
class _IntelligenceMeter extends ConsumerWidget {
  const _IntelligenceMeter({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votesAsync = ref.watch(allTruthVotesProvider(requestId));
    final votes = votesAsync.value ?? const [];

    final trueCount = votes.where((v) => v.verdict).length;
    final falseCount = votes.length - trueCount;
    final total = trueCount + falseCount;

    if (total == 0) {
      return Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('投票なし', style: Theme.of(context).textTheme.labelSmall),
      );
    }

    final truePct = (trueCount / total * 100).round();
    final falsePct = 100 - truePct;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 28,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                if (trueCount > 0) Expanded(flex: trueCount, child: Container(color: Colors.green)),
                if (falseCount > 0) Expanded(flex: falseCount, child: Container(color: Colors.red)),
              ],
            ),
            Center(
              child: Text(
                '真 $truePct%（$trueCount） 偽 $falsePct%（$falseCount）',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
                ),
              ),
            ),
          ],
        ),
      ),
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

/// design/product.md 3.4.3節。チケット購入前に必ず確認ダイアログを挟み、誤タップによる
/// 意図しないTP消費を防ぐ（購入枚数・消費TPを明示する）。
Future<bool?> _confirmTicketPurchase(BuildContext context, int count) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('チケットを購入しますか？'),
      content: Text('投票権チケット $count枚を ${count * 100} TPで購入します。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('購入する'),
        ),
      ],
    ),
  );
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
                  final confirmed = await _confirmTicketPurchase(context, count);
                  if (confirmed != true || !context.mounted) return;
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
