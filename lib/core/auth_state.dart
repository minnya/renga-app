import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Supabase Authのセッション変化を配信するStreamProvider。
/// design/system.md 3章「Auth」のセッション状態をアプリ全体でRiverpod経由で参照するために使う。
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// 現在ログイン中のユーザー（未ログイン時はnull）。
final currentUserProvider = Provider<User?>((ref) {
  final authStateAsync = ref.watch(authStateChangesProvider);
  return authStateAsync.whenOrNull(data: (state) => state.session?.user) ??
      supabase.auth.currentUser;
});
