import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  /// `.env`の`GOOGLE_OAUTH_CLIENT_ID`を読み込む（未設定時は`AuthFailure`を投げる）。
  String _requireGoogleClientId() {
    final clientId = dotenv.env['GOOGLE_OAUTH_CLIENT_ID'];
    if (clientId == null || clientId.isEmpty) {
      throw AuthFailure(
        'GOOGLE_OAUTH_CLIENT_ID が .env に設定されていません。'
        '.env.example を参考に設定してください。',
      );
    }
    return clientId;
  }

  /// `GoogleSignIn.instance`を初期化する。ボタン表示・サインイン開始のどちらの前にも必要。
  ///
  /// google_sign_in_webは`serverClientId`を受け付けない
  /// （`assert(params.serverClientId == null, 'serverClientId is not supported on Web.')`）ため、
  /// Webでは代わりに`clientId`として同じ値を渡す。ネイティブ（Android/iOS）は`serverClientId`のままでよい。
  ///
  /// `GoogleSignIn.instance.initialize()`は二重呼び出しで`Bad state: init() has already been
  /// called.`を投げるため、アプリ全体で1回だけ実行されるようFutureをキャッシュする
  /// （`LoginPage`は認証状態のリダイレクトで複数回マウントされ得るため）。
  Future<void> initializeGoogleSignIn() {
    return _googleSignInInitFuture ??= () async {
      final clientId = _requireGoogleClientId();
      // GoogleにはSHA256でハッシュ化したnonceを渡し、IDトークンの`nonce`クレームに
      // そのハッシュ値が埋め込まれるようにする。Supabase側にはハッシュ化前の生nonceを渡すと、
      // Supabaseがサーバー側で同じくSHA256ハッシュを取って両者を比較検証する
      // （生のまま両方に渡すと「invalid nonce: Nonces mismatch」エラーになる）。
      _googleSignInRawNonce = _generateNonce();
      final hashedNonce = _sha256ofString(_googleSignInRawNonce!);
      if (kIsWeb) {
        await GoogleSignIn.instance.initialize(clientId: clientId, nonce: hashedNonce);
      } else {
        await GoogleSignIn.instance.initialize(serverClientId: clientId, nonce: hashedNonce);
      }
    }();
  }

  static Future<void>? _googleSignInInitFuture;
  static String? _googleSignInRawNonce;

  /// Google/Supabase双方に渡す、認証1回分のランダムなnonce文字列を生成する。
  static String _generateNonce([int length = 32]) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  static String _sha256ofString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Google Sign-InでログインしSupabase Authと連携する（Android/iOS向け）。
  ///
  /// design/system.md 9章の方式に従い、`google_sign_in`パッケージでGoogle認証を行い、
  /// 取得したIDトークン（+アクセストークン）を`Supabase.instance.client.auth.signInWithIdToken`
  /// に渡してSupabase Auth側のセッションを確立する。
  ///
  /// **Web版では使えない**: google_sign_in_webはプライバシー保護（FedCM）の都合上
  /// `authenticate()`のプログラム的な呼び出しを`UnimplementedError`にする。Webでは
  /// 代わりに[google_signin_button.dart]のGIS公式ボタンをユーザーがクリックし、
  /// [handleGoogleAuthenticationEvent]で結果を受け取る（`login_page.dart`を参照）。
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _requireGoogleClientId();
      try {
        final googleUser = await GoogleSignIn.instance.authenticate();
        await _signInToSupabaseWithGoogleUser(googleUser);
      } on GoogleSignInException catch (e) {
        throw AuthFailure('Googleサインインに失敗しました: ${e.description ?? e.code}');
      } on AuthException catch (e) {
        throw AuthFailure(e.message);
      }
    });
  }

  /// Web版。GIS公式ボタン（`GoogleSignIn.instance.authenticationEvents`）経由のサインイン結果を
  /// 受け取り、Supabase Authと連携する。`login_page.dart`が`authenticationEvents`を購読して呼び出す。
  Future<void> handleGoogleAuthenticationEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is! GoogleSignInAuthenticationEventSignIn) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        await _signInToSupabaseWithGoogleUser(event.user);
      } on AuthException catch (e) {
        throw AuthFailure(e.message);
      }
    });
  }

  Future<void> _signInToSupabaseWithGoogleUser(GoogleSignInAccount googleUser) async {
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
      nonce: _googleSignInRawNonce,
    );
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(AuthController.new);
