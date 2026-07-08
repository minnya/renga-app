import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  /// Google Sign-InでログインしSupabase Authと連携する。
  ///
  /// design/system.md 9章の方式に従い、`google_sign_in`パッケージでGoogle認証を行い、
  /// 取得したIDトークン（+アクセストークン）を`Supabase.instance.client.auth.signInWithIdToken`
  /// に渡してSupabase Auth側のセッションを確立する。
  ///
  /// クライアントID（Web/サーバー用）は`.env`の`GOOGLE_OAUTH_CLIENT_ID`から読み込む
  /// （未設定の場合はエラーとして扱う。実APIキーが無い開発環境ではボタン押下時に失敗するのみで、
  /// アプリの起動やビルド自体は妨げない）。
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final serverClientId = dotenv.env['GOOGLE_OAUTH_CLIENT_ID'];
      if (serverClientId == null || serverClientId.isEmpty) {
        throw AuthFailure(
          'GOOGLE_OAUTH_CLIENT_ID が .env に設定されていません。'
          '.env.example を参考に設定してください。',
        );
      }

      try {
        final googleSignIn = GoogleSignIn.instance;
        await googleSignIn.initialize(serverClientId: serverClientId);

        final googleUser = await googleSignIn.authenticate();
        final idToken = googleUser.authentication.idToken;
        if (idToken == null) {
          throw AuthFailure('GoogleアカウントからIDトークンを取得できませんでした');
        }

        // アクセストークンはSupabase側では必須ではないが、あわせて渡すことでGoogle側の
        // 追加スコープ（email等）の権限情報も連携できる。取得に失敗しても致命的ではないため無視する。
        String? accessToken;
        try {
          final authorization =
              await googleUser.authorizationClient.authorizationForScopes(['email']) ??
              await googleUser.authorizationClient.authorizeScopes(['email']);
          accessToken = authorization.accessToken;
        } catch (_) {
          accessToken = null;
        }

        await supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );
      } on GoogleSignInException catch (e) {
        throw AuthFailure('Googleサインインに失敗しました: ${e.description ?? e.code}');
      } on AuthException catch (e) {
        throw AuthFailure(e.message);
      }
    });
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(AuthController.new);
