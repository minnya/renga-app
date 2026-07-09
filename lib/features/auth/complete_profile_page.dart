import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';
import '../../l10n/gen/app_localizations.dart';
import 'profile_completion_provider.dart';
import 'profile_setup_form.dart';

/// design/product.md 4章「Complete Profile」/ design/system.md 3章「Auth」。
///
/// Googleサインインで**新規に**アカウントが作成された場合、`handle_new_user`トリガーが
/// `profiles.profile_completed = false`で行を作成する。`lib/app/router.dart`の`redirect`が
/// これを検知し、オンボーディングクイズと同じ強制リダイレクトのパターンでこの画面以外への
/// アクセスをブロックする。signup_page.dartのメール登録と同じ[ProfileSetupUsernameField]を
/// 使い、username入力・保存が完了して初めてホームへ進めるようにする。
class CompleteProfilePage extends ConsumerStatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  ConsumerState<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends ConsumerState<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) {
      return l10n.completeProfileUsernameRequired;
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    try {
      await supabase
          .from('profiles')
          .update({
            'username': _usernameController.text.trim(),
            'profile_completed': true,
          })
          .eq('id', userId);
      ref.invalidate(profileCompletedProvider);
      if (!mounted) return;
      context.go('/');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      // PostgreSQLのunique_violation（profiles_username_key）。生のエラーメッセージを
      // そのままユーザーに見せず、ユーザー名重複であることが分かる文言に置き換える。
      final message = e.code == '23505'
          ? l10n.completeProfileUsernameTaken
          : l10n.completeProfileFailedMessage(e.message);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.completeProfileAppBarTitle), automaticallyImplyLeading: false),
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
                  Text(l10n.completeProfileDescription),
                  const SizedBox(height: 24),
                  ProfileSetupUsernameField(
                    controller: _usernameController,
                    validator: _validateUsername,
                    autofocus: true,
                    labelText: l10n.completeProfileUsernameLabel,
                    helperText: l10n.completeProfileUsernameHelper,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.completeProfileSubmitButton),
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
