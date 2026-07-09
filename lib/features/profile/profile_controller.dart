import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';

/// 指定したユーザーIDの `profiles` 行を取得するProvider。
///
/// `public.profiles` は誰でもselect可能（RLS: `profiles are publicly readable`）なので、
/// 自分以外のプロフィール取得にも将来的に流用できる。
final profileProvider = FutureProvider.family<Map<String, dynamic>, String>((
  ref,
  userId,
) async {
  final row = await supabase.from('profiles').select().eq('id', userId).single();
  return row;
});

/// 全ユーザー平均のキャッシュ（`score_stats`、シングルトン行）を取得するProvider。
///
/// design/system.md 1章・2章。プロフィール画面のIQ/Influence表示の「平均より+N」表示に使う。
/// `score_stats` は誰でもselect可能（RLS: `score_stats are publicly readable`）。
final scoreStatsProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final row = await supabase.from('score_stats').select().maybeSingle();
  return row;
});

/// 指定したユーザーの日次スコア推移（`user_score_history`）を日付昇順で取得するProvider。
///
/// design/system.md 1章・2章「日次推移」。プロフィール画面の前日比・推移グラフ表示に使う。
/// 直近90日分に絞り、グラフ・前日比計算に十分なデータ量に留める。
final scoreHistoryProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  userId,
) async {
  final rows = await supabase
      .from('user_score_history')
      .select()
      .eq('user_id', userId)
      .order('snapshot_date', ascending: true)
      .limit(90);
  return List<Map<String, dynamic>>.from(rows);
});

/// プロフィールの更新処理をまとめたコントローラー。
///
/// `display_name` / `bio` の更新のみを扱う（design/system.md 1章の profiles スキーマのうち
/// 本人が編集可能な項目）。更新成功後は該当ユーザーの [profileProvider] をinvalidateし、
/// 画面側が最新値を再取得できるようにする。
class ProfileController {
  ProfileController(this.ref);

  final Ref ref;

  Future<void> updateProfile({
    required String userId,
    required String displayName,
    required String bio,
    String? websiteUrl,
    String? location,
  }) async {
    await supabase.from('profiles').update({
      'display_name': displayName,
      'bio': bio,
      'website_url': ?websiteUrl,
      'location': ?location,
    }).eq('id', userId);

    ref.invalidate(profileProvider(userId));
  }

  /// design/product.md 3.10節「プロフィール詳細設定」。
  /// アバター画像をSupabase Storage（`avatars`バケット）にアップロードし、
  /// 返却されたURLを`profiles.avatar_url`の更新に使用する。
  Future<String> uploadAvatarImage({
    required String userId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final uniqueName =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 31)}.$fileExt';
    final path = '$userId/$uniqueName';

    await supabase.storage.from('avatars').uploadBinary(path, bytes);
    return supabase.storage.from('avatars').getPublicUrl(path);
  }
}

final profileControllerProvider = Provider<ProfileController>((ref) {
  return ProfileController(ref);
});
