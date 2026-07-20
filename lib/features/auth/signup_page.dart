import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/locale_controller.dart';
import '../../l10n/gen/app_localizations.dart';
import 'auth_controller.dart';
import 'google_signin_button.dart';
import 'profile_setup_form.dart';

/// メールアドレス/パスワードまたはGoogleでの新規登録画面。
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSubscription;
  bool _googleSignInReady = false;
  // design/product.md 3.11節「Settings（設定）画面」: サインアップ時にも表示言語を選択させる。
  // 端末言語追従は選ばせず、アプリが対応するロケールのみを選択肢とする。既定はEnglish。
  Locale _selectedLocale = const Locale('en');

  @override
  void initState() {
    super.initState();
    _initGoogleSignIn();
  }

  /// login_page.dartと同様、Web版はGIS公式ボタンの`authenticationEvents`を購読して
  /// Supabase Authと連携する（`signInWithIdToken`は未登録メールなら新規アカウントを作成する）。
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
      // GOOGLE_OAUTH_CLIENT_ID未設定時などはボタンを出さないだけに留める。
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
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
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    // design/product.md 3.11節: 選択した言語を即座にアプリ全体の表示言語へ反映する
    // （確認メール送信後の画面や、確認完了までの間の画面もこの言語で表示されるようにするため）。
    await ref.read(localeProvider.notifier).setLocale(_selectedLocale);
    await ref
        .read(authControllerProvider.notifier)
        .signUp(
          email: email,
          password: _passwordController.text,
          username: username.isEmpty ? null : username,
          locale: _selectedLocale.languageCode,
        );
    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    if (!state.hasError) {
      final l10n = AppLocalizations.of(context);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.signupAppBarTitle),
          content: Text(l10n.signupCheckEmailMessage(email)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.signupCheckEmailOkButton),
            ),
          ],
        ),
      );
      if (!mounted) return;
      context.go('/login');
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
        final message = error is EmailAlreadyRegisteredFailure
            ? l10n.authEmailAlreadyRegistered
            : error is AuthFailure
                ? error.message
                : l10n.signupFailedMessage('$error');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.signupAppBarTitle)),
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
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(labelText: l10n.authPasswordLabel),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 16),
                  ProfileSetupUsernameField(controller: _usernameController),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Locale>(
                    initialValue: _selectedLocale,
                    decoration: InputDecoration(labelText: l10n.signupLanguageLabel),
                    items: [
                      DropdownMenuItem(
                        value: const Locale('en'),
                        child: Text(l10n.settingsLanguageEnglish),
                      ),
                      DropdownMenuItem(
                        value: const Locale('ja'),
                        child: Text(l10n.settingsLanguageJapanese),
                      ),
                    ],
                    onChanged: isLoading
                        ? null
                        : (value) {
                            if (value != null) setState(() => _selectedLocale = value);
                          },
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
                        : Text(l10n.signupSubmitButton),
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
                    Center(
                      child: SizedBox(width: 300, height: 44, child: buildGoogleSignInButton()),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: isLoading ? null : _submitWithGoogle,
                      icon: const Icon(Icons.g_mobiledata),
                      label: Text(l10n.signupGoogleButton),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isLoading ? null : () => context.go('/login'),
                    child: Text(l10n.signupGoToLogin),
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
