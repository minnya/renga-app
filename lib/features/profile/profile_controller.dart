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
  }) async {
    await supabase.from('profiles').update({
      'display_name': displayName,
      'bio': bio,
    }).eq('id', userId);

    ref.invalidate(profileProvider(userId));
  }
}

final profileControllerProvider = Provider<ProfileController>((ref) {
  return ProfileController(ref);
});
