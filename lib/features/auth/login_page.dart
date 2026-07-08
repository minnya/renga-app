import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';

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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'メールアドレスを入力してください';
    }
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(value.trim())) {
      return '正しいメールアドレスの形式で入力してください';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'パスワードを入力してください';
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
    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        final error = next.error;
        final message = error is AuthFailure ? error.message : 'ログインに失敗しました: $error';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('ログイン')),
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
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'メールアドレス'),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'パスワード'),
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
                        : const Text('ログイン'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('または'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : _submitWithGoogle,
                    icon: const Icon(Icons.g_mobiledata),
                    label: const Text('Googleでログイン'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isLoading ? null : () => context.go('/signup'),
                    child: const Text('アカウントをお持ちでない方はこちら'),
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
