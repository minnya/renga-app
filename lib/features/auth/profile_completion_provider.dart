import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';

/// design/system.md 3章「Auth」: Googleサインイン新規登録直後のユーザーは
/// `profiles.profile_completed = false`で作成される（`handle_new_user`トリガー）。
/// [lib/app/router.dart]の`redirect`がこれを見て`/complete-profile`へ強制遷移させる、
/// `hasCompletedOnboardingProvider`（quiz_controller.dart）と同様のパターン。
final profileCompletedProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return true;

  final row = await supabase
      .from('profiles')
      .select('profile_completed')
      .eq('id', userId)
      .maybeSingle();
  if (row == null) return true;
  return row['profile_completed'] as bool? ?? true;
});
