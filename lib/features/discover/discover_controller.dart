import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/supabase_client.dart';
import 'domain_post.dart';
import 'domain_score.dart';

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
