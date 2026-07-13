import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';
import '../feed/feed_controller.dart' show postSelectColumns;
import '../feed/post.dart';
import '../profile/profile_controller.dart';
import 'domain_post.dart';
import 'domain_score.dart';
import 'truth_judgment.dart';

/// design/product.md 3.5節「AI自動専門家発掘システム」のドメイン一覧。
///
/// 日本標準産業分類の大分類20区分（Edge Function `label_post_domain` が投稿本文の
/// 分類に用いるタクソノミーと一致させる）。キーは `domain_scores.domain` /
/// `posts.domain_labels` と完全一致させる必要がある。
const domainTaxonomy = <String>[
  '農業_林業',
  '漁業',
  '鉱業_採石業_砂利採取業',
  '建設業',
  '製造業',
  '電気_ガス_熱供給_水道業',
  '情報通信業',
  '運輸業_郵便業',
  '卸売業_小売業',
  '金融業_保険業',
  '不動産業_物品賃貸業',
  '学術研究_専門技術サービス業',
  '宿泊業_飲食サービス業',
  '生活関連サービス業_娯楽業',
  '教育_学習支援業',
  '医療_福祉',
  '複合サービス事業',
  'サービス業_他に分類されないもの',
  '公務',
  '分類不能の産業',
];

/// ドメインの内部キー（DB問い合わせに使う値。アンダースコア区切り）から、
/// 表示用のラベル（読みやすいよう「・」区切り）へ変換する。
String domainDisplayLabel(String key) => key.replaceAll('_', '・');

/// Discover画面で現在選択中のドメイン（デフォルトは先頭のドメイン）。
final selectedDomainProvider = StateProvider<String>((ref) => domainTaxonomy.first);

/// design/product.md 3.16節「Discoverのキーワード検索」。現在入力中の検索キーワード
/// （初期値は空文字＝未検索）。
final discoverSearchKeywordProvider = StateProvider<String>((ref) => '');

/// design/system.md 1章の `domain_scores` テーブルから、指定ドメインのランキング
/// （スコア降順、最大50件）を取得する。`profiles` をネストselectしてusername等も取得する。
/// `domain_scores` は誰でもselect可能なRLSのため、未ログインでも取得できる。
final domainRankingProvider = FutureProvider.family<List<DomainScore>, String>((
  ref,
  domain,
) async {
  final rows = await supabase
      .from('domain_scores')
      .select('user_id, domain, score, badge_tier, updated_at, profiles(username, avatar_url)')
      .eq('domain', domain)
      .order('score', ascending: false)
      .limit(50);

  return rows.map((row) => DomainScore.fromMap(row)).toList();
});

/// design/system.md 6.1節「ドメインラベリング」。指定ドメインが`domain_labels`に
/// 含まれる投稿一覧（作成日時降順、最大50件）を取得する。Edge Function
/// `label_post_domain` が投稿作成時に本文をGeminiで分類し、`posts.domain_labels`
/// （text[]列）へ書き込む想定。`posts` は誰でもselect可能なRLSのため、未ログインでも
/// 取得できる。
final domainPostsProvider = FutureProvider.family<List<DomainPost>, String>((
  ref,
  domain,
) async {
  final rows = await supabase
      .from('posts')
      .select('id, body, media_type, media_urls, created_at, author_id, profiles(username, avatar_url)')
      .contains('domain_labels', [domain])
      .order('created_at', ascending: false)
      .limit(50);

  return rows.map((row) => DomainPost.fromMap(row)).toList();
});

/// design/product.md 3.16節「Discoverのキーワード検索」。選択中ドメイン
/// （`selectedDomainProvider`）とキーワード（`discoverSearchKeywordProvider`）の両方で
/// 投稿を絞り込む。キーワードが空の場合はドメイン絞り込みのみ（`domainPostsProvider`と同じ
/// 結果）になる。
final discoverFilteredPostsProvider = FutureProvider<List<DomainPost>>((ref) async {
  final domain = ref.watch(selectedDomainProvider);
  final keyword = ref.watch(discoverSearchKeywordProvider);

  var query = supabase
      .from('posts')
      .select('id, body, media_type, media_urls, created_at, author_id, profiles(username, avatar_url)')
      .contains('domain_labels', [domain]);

  final trimmedKeyword = keyword.trim();
  if (trimmedKeyword.isNotEmpty) {
    query = query.ilike('body', '%$trimmedKeyword%');
  }

  final rows = await query.order('created_at', ascending: false).limit(50);

  return rows.map((row) => DomainPost.fromMap(row)).toList();
});

/// design/product.md 2.1節「画面別の権限モデル」。ログイン中のユーザーがDiscoverの
/// `Create`権限（上位25%以上、`is_top_intellect_tier`）を持つかどうか。
/// 実際の許可判定は常にサーバー側（RLS + RPC内チェック）で行うため、これはUI表示の
/// 出し分け専用（あいまいな場合は非表示側に倒す）。
final isTopIntellectTierProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  try {
    final profile = await ref.watch(profileProvider(user.id).future);
    final percentile = profile['intellect_percentile'] as num?;
    return percentile != null && percentile <= 25;
  } catch (_) {
    // 取得失敗時は権限UIを出さない側に倒す。
    return false;
  }
});

/// design/product.md 2.1節「Discover」画面のCreate投稿一覧
/// （`posts.context = 'discover'`の投稿、作成日時降順・最大50件）。
final discoverContextPostsProvider = FutureProvider<List<Post>>((ref) async {
  final rows = await supabase
      .from('posts')
      .select(postSelectColumns)
      .eq('context', 'discover')
      .order('created_at', ascending: false)
      .limit(50);
  return rows.map((row) => Post.fromMap(row)).toList();
});

/// design/product.md 3.5節「Feed → Discoverのキュレーション」。`discover_promotions`経由で
/// Discoverへ引き上げられたFeed投稿（元のpostは`context = 'feed'`のまま、
/// キュレーションは加算的でリポストに近い）一覧。
final discoverPromotedPostsProvider = FutureProvider<List<Post>>((ref) async {
  final rows = await supabase
      .from('discover_promotions')
      .select('post_id, created_at, posts($postSelectColumns)')
      .order('created_at', ascending: false)
      .limit(50);

  return rows
      .map((row) => row['posts'])
      .whereType<Map>()
      .map((post) => Post.fromMap(Map<String, dynamic>.from(post)))
      .toList();
});

/// [discoverContextPostsProvider]（Discover新規投稿）と[discoverPromotedPostsProvider]
/// （Feedからの引き上げ）を作成日時降順にマージした、Discover画面に表示する投稿一覧。
final discoverPostsProvider = FutureProvider<List<Post>>((ref) async {
  final directPosts = await ref.watch(discoverContextPostsProvider.future);
  final promotedPosts = await ref.watch(discoverPromotedPostsProvider.future);

  final byId = <String, Post>{};
  for (final post in [...directPosts, ...promotedPosts]) {
    byId[post.id] = post;
  }
  final merged = byId.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return merged;
});

/// design/product.md 3.4節「真偽投票」。指定投稿の真偽審判リクエスト（存在すれば1件、
/// `unique(post_id)`）。リクエストが起票されていない投稿は`null`。
final truthJudgmentRequestProvider =
    FutureProvider.family<TruthJudgmentRequest?, String>((ref, postId) async {
  final row = await supabase
      .from('truth_judgment_requests')
      .select()
      .eq('post_id', postId)
      .maybeSingle();
  return row == null ? null : TruthJudgmentRequest.fromMap(row);
});

/// ログイン中のユーザーが指定の真偽審判リクエストに既に投票済みかどうか
/// （`truth_votes`は`unique(request_id, user_id)`のため再投票不可。読み取り専用表示に使う）。
final myTruthVoteProvider =
    FutureProvider.family<TruthVote?, String>((ref, requestId) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final row = await supabase
      .from('truth_votes')
      .select()
      .eq('request_id', requestId)
      .eq('user_id', user.id)
      .maybeSingle();
  return row == null ? null : TruthVote.fromMap(row);
});

/// design/product.md 3.4.4節「2階建てインテリジェンス・メーター」。指定リクエストの全投票
/// （Top5%/Top25%の階層別内訳表示に使う）。`truth_votes`は誰でもselect可能なRLSのため、
/// 未ログインでも取得できるが、UI側はブラインド投票フェーズ中（3.4.2節）は自分が投票する
/// までこの結果を比率として見せない。
final allTruthVotesProvider =
    FutureProvider.family<List<TruthVote>, String>((ref, requestId) async {
  final rows = await supabase.from('truth_votes').select().eq('request_id', requestId);
  return rows.map((row) => TruthVote.fromMap(row)).toList();
});

/// design/product.md 3.4.3節「投票権チケット」エコノミー。ログイン中ユーザーの保有チケット枚数。
/// `user_assets`は自分の行のみselect可能なRLSのため、行が存在しない場合は0枚として扱う。
final ticketCountProvider = FutureProvider<int>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;
  final row = await supabase
      .from('user_assets')
      .select('ticket_count')
      .eq('user_id', user.id)
      .maybeSingle();
  return (row?['ticket_count'] as int?) ?? 0;
});

/// Discover画面のCreate投稿・真偽審判リクエスト・Feed→Discover引き上げをまとめて扱う
/// コントローラー。実際の権限・残高チェックはすべてRPC側（migration参照）で行われるため、
/// ここではRPC呼び出しと関連Providerのinvalidateのみを担う。
class DiscoverController {
  DiscoverController(this.ref);

  final Ref ref;

  /// design/product.md 2.1節「Discoverの`Create`権限」。上位25%以上のユーザーのみ成功する
  /// （それ以外は`create_discover_post` RPCが例外を投げる）。
  Future<void> createDiscoverPost({required String body, required num stakedTp}) async {
    await supabase.rpc(
      'create_discover_post',
      params: {'p_body': body.trim(), 'p_staked_tp': stakedTp},
    );
    ref.invalidate(discoverContextPostsProvider);
    ref.invalidate(discoverPostsProvider);
  }

  /// design/product.md 3.5節「Feed → Discoverのキュレーション」。
  Future<void> promotePostToDiscover({required String postId, required num tpCost}) async {
    await supabase.rpc(
      'promote_post_to_discover',
      params: {'p_post_id': postId, 'p_tp_cost': tpCost},
    );
    ref.invalidate(discoverPromotedPostsProvider);
    ref.invalidate(discoverPostsProvider);
  }

  /// design/product.md 3.4節「リクエスト」。対象投稿は`context = 'discover'`である必要がある
  /// （それ以外は`request_truth_judgment` RPCが例外を投げる）。
  Future<void> requestTruthJudgment({required String postId}) async {
    await supabase.rpc('request_truth_judgment', params: {'p_post_id': postId});
    ref.invalidate(truthJudgmentRequestProvider(postId));
  }

  /// design/product.md 3.4.2節「投票」。投票権チケットを1枚消費する（TP増減は発生しない）。
  /// 投票資格（上位25%かつ投稿者本人と同格以上・自己投票不可）とチケット保有は
  /// `cast_truth_vote` RPC側で検証され、違反時は例外（`PostgrestException.message`が日本語）を返す。
  Future<void> castTruthVote({
    required String requestId,
    required String postId,
    required bool verdict,
  }) async {
    await supabase.rpc(
      'cast_truth_vote',
      params: {'p_request_id': requestId, 'p_verdict': verdict},
    );
    ref.invalidate(truthJudgmentRequestProvider(postId));
    ref.invalidate(myTruthVoteProvider(requestId));
    ref.invalidate(allTruthVotesProvider(requestId));
    ref.invalidate(ticketCountProvider);
  }

  /// design/product.md 3.4.3節「投票権チケット」エコノミー。一般ユーザー（Top25%未満）が
  /// 1枚＝100TPでチケットを購入する。上位ユーザーへのデイリー無料配布は`grant_daily_tickets`
  /// （pg_cron経由、サーバー側のみ）が担うため、クライアントからは呼び出さない。
  Future<void> purchaseTickets({required int ticketCount}) async {
    await supabase.rpc('purchase_tickets', params: {'p_ticket_count': ticketCount});
    ref.invalidate(ticketCountProvider);
  }
}

final discoverControllerProvider = Provider<DiscoverController>((ref) {
  return DiscoverController(ref);
});
