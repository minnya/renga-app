import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/supabase_client.dart';
import 'domain_score.dart';

/// design/product.md 3.5節「AI自動専門家発掘システム」に例示されるドメイン一覧。
/// キーは `domain_scores.domain` / `posts.domain_labels` と一致させる想定。
const domainOptions = <String, String>{
  'medical': '医療',
  'automotive': '自動車',
  'history': '歴史',
  'it': 'IT',
  'finance': '金融',
};

/// Discover画面で現在選択中のドメイン（デフォルトは先頭のドメイン）。
final selectedDomainProvider = StateProvider<String>((ref) => domainOptions.keys.first);

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
