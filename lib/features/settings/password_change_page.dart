import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes;

import '../../core/supabase_client.dart';
import '../../l10n/gen/app_localizations.dart';

/// design/product.md 3.11節「Settings（設定）画面」のパスワード変更サブページ。
///
/// 現在のパスワード確認は求めない（Supabase Authのセッションで認証済みのため）。
/// 新パスワード入力＋確認入力のみを行い、`supabase.auth.updateUser(password: ...)`で更新する。
class PasswordChangePage extends StatefulWidget {
  const PasswordChangePage({super.key});

  @override
  State<PasswordChangePage> createState() => _PasswordChangePageState();
}

class _PasswordChangePageState extends State<PasswordChangePage> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final l10n = AppLocalizations.of(context);
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.length < 6) {
      setState(() => _errorText = l10n.passwordChangeTooShortError);
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _errorText = l10n.passwordChangeMismatchError);
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.passwordChangeSuccess)),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = l10n.passwordChangeError('$e'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPasswordChangeLabel)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.passwordChangeNewLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.passwordChangeConfirmLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submitting ? null : _handleSubmit(),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _handleSubmit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.passwordChangeSubmitButton),
            ),
          ],
        ),
      ),
    );
  }
}
