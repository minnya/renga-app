import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Supabase Authの認証失敗（メール/パスワード誤り、重複メール等）をUI側に伝えるための例外。
/// [message] はSupabaseの[AuthException.message]、もしくは想定外エラーの[toString]を保持する。
class AuthFailure implements Exception {
  AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// メール/パスワードでのログイン・サインアップを行うコントローラ。
///
/// 状態は`AsyncValue<void>`で表現し、UI側は
/// - `authControllerProvider.select((s) => s.isLoading)` 等でローディング判定
/// - `ref.listen(authControllerProvider, ...)` の`next.hasError`でエラー判定
/// といった形で参照する想定。
///
/// 成功後の画面遷移（`context.go('/')`）はこのコントローラでは行わず、呼び出し元のページで
/// 明示的に行う（コントローラはSupabase呼び出しの結果のみを管理する）。
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // 初期状態は「待機中（データなし）」。認証操作はsignInWithPassword/signUpから呼ばれる。
  }

  /// メールアドレスとパスワードでログインする。
  Future<void> signInWithPassword({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        await supabase.auth.signInWithPassword(email: email, password: password);
      } on AuthException catch (e) {
        throw AuthFailure(e.message);
      }
    });
  }

  /// メールアドレス・パスワードでサインアップする。
  ///
  /// [username]が指定されていれば`raw_user_meta_data`経由で`handle_new_user`トリガーへ渡し、
  /// `profiles.username`に反映させる。未指定（null・空文字）の場合は渡さず、
  /// トリガー側のデフォルト（ユーザーID）に委ねる。
  Future<void> signUp({required String email, required String password, String? username}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: (username != null && username.isNotEmpty) ? {'username': username} : null,
        );
      } on AuthException catch (e) {
        throw AuthFailure(e.message);
      }
    });
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(AuthController.new);
