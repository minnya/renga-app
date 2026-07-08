import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import 'battle.dart';

/// design/product.md 3.4節・4章「Battle Tab」のバトル一覧を取得する。
///
/// 対象投稿・挑戦投稿の `body` と投稿者 `username` を併せて取得するため、
/// Supabase Dartのネストselectで2つの `posts` への外部キーをそれぞれ別名指定する。
/// `battles` は誰でもselect可能なRLSのため、未ログインでも取得できる想定。
final battleListProvider = FutureProvider<List<Battle>>((ref) async {
  final rows = await supabase
      .from('battles')
      .select(
        'id, target_post_id, challenger_id, challenger_post_id, status, '
        'challenger_stake_tp, defender_stake_tp, winner, resolves_at, created_at, '
        'target_post:posts!battles_target_post_id_fkey(body, profiles(username)), '
        'challenger_post:posts!battles_challenger_post_id_fkey(body, profiles(username))',
      )
      .order('created_at', ascending: false)
      .limit(50);

  return rows.map((row) => Battle.fromMap(row)).toList();
});

/// バトル詳細を1件取得する。
final battleDetailProvider = FutureProvider.family<Battle, String>((ref, battleId) async {
  final row = await supabase
      .from('battles')
      .select(
        'id, target_post_id, challenger_id, challenger_post_id, status, '
        'challenger_stake_tp, defender_stake_tp, winner, resolves_at, created_at, '
        'target_post:posts!battles_target_post_id_fkey(body, profiles(username)), '
        'challenger_post:posts!battles_challenger_post_id_fkey(body, profiles(username))',
      )
      .eq('id', battleId)
      .single();

  return Battle.fromMap(row);
});

/// 指定バトルに対する観客ベット一覧（side別の集計・自分のベット確認用の土台）。
final battleBetsProvider = FutureProvider.family<List<BattleBet>, String>((ref, battleId) async {
  final rows = await supabase
      .from('battle_bets')
      .select()
      .eq('battle_id', battleId)
      .order('created_at', ascending: false);

  return rows.map((row) => BattleBet.fromMap(row)).toList();
});

/// バトルへの観客ベットを行うコントローラ。
///
/// design/system.md 12章のEdge Function（精算ロジック）は未実装のため、
/// ここでは `battle_bets` へのシンプルなinsertのみを行う（TP残高チェック等は対象外）。
class BattleController {
  BattleController(this.ref);

  final Ref ref;

  Future<void> placeBet({
    required String battleId,
    required String userId,
    required String side,
    required num amountTp,
  }) async {
    if (side != 'challenger' && side != 'defender') {
      throw ArgumentError('side は challenger または defender を指定してください');
    }
    if (amountTp <= 0) {
      throw ArgumentError('ベット額は1TP以上を指定してください');
    }

    await supabase.from('battle_bets').insert({
      'battle_id': battleId,
      'user_id': userId,
      'side': side,
      'amount_tp': amountTp,
    });

    ref.invalidate(battleBetsProvider(battleId));
  }
}

final battleControllerProvider = Provider<BattleController>((ref) {
  return BattleController(ref);
});
