import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../l10n/gen/app_localizations.dart';
import 'auth_controller.dart';
import 'google_signin_button.dart';

/// メールアドレス/パスワードでのログイン画面。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSubscription;
  bool _googleSignInReady = false;

  @override
  void initState() {
    super.initState();
    _initGoogleSignIn();
  }

  /// design/system.md 9章。Web版はGIS公式ボタンをクリックすると
  /// `authenticationEvents`にサインイン結果が流れてくるため、ここで購読して
  /// `auth_controller.dart`側でSupabase Authと連携する。
  Future<void> _initGoogleSignIn() async {
    try {
      await ref.read(authControllerProvider.notifier).initializeGoogleSignIn();
      if (kIsWeb) {
        _googleAuthSubscription = GoogleSignIn.instance.authenticationEvents.listen((
          event,
        ) async {
          await ref.read(authControllerProvider.notifier).handleGoogleAuthenticationEvent(event);
          if (!mounted) return;
          final state = ref.read(authControllerProvider);
          if (!state.hasError) {
            context.go('/');
          }
        });
      }
      if (mounted) setState(() => _googleSignInReady = true);
    } catch (_) {
      // GOOGLE_OAUTH_CLIENT_ID未設定時などはボタンを出さないだけに留める
      // （メール/パスワード認証は引き続き利用できる）。
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _googleAuthSubscription?.cancel();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) {
      return l10n.authEmailRequired;
    }
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(value.trim())) {
      return l10n.authEmailInvalid;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context).authPasswordRequired;
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await ref
        .read(authControllerProvider.notifier)
        .signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    if (!state.hasError) {
      context.go('/');
    }
  }

  Future<void> _submitWithGoogle() async {
    await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    if (!state.hasError) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        final error = next.error;
        final message = error is AuthFailure ? error.message : l10n.loginFailedMessage('$error');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginAppBarTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/icon/renga_icon_1024.png',
                      width: 72,
                      height: 72,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(labelText: l10n.authEmailLabel),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(labelText: l10n.authPasswordLabel),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isLoading ? null : _submit,
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.loginSubmitButton),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(l10n.loginOrDivider),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!_googleSignInReady)
                    const SizedBox.shrink()
                  else if (kIsWeb)
                    // design/system.md 9章補足: WebはGIS公式ボタンをそのまま描画する
                    // （`authenticate()`のプログラム的な呼び出しは`UnimplementedError`になるため）。
                    // renderButton()はHtmlElementViewを内包し固有サイズを持たないため、
                    // 明示的にサイズを与える必要がある。
                    Center(
                      child: SizedBox(width: 300, height: 44, child: buildGoogleSignInButton()),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: isLoading ? null : _submitWithGoogle,
                      icon: const Icon(Icons.g_mobiledata),
                      label: Text(l10n.loginGoogleButton),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isLoading ? null : () => context.go('/signup'),
                    child: Text(l10n.loginGoToSignup),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
