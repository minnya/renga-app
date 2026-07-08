import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_state.dart';
import '../../core/supabase_client.dart';
import '../../l10n/gen/app_localizations.dart';
import '../profile/profile_controller.dart';

/// design/product.md 3.11節「Settings（設定）画面」のアカウント削除サブページ。
/// design/system.md 9章「アカウント削除」。
///
/// クライアントから`auth.users`を直接削除できないため、Supabase Edge Function
/// `delete_account`（サービスロールキー保持）を呼び出して削除する。誤操作防止のため、
/// 削除ボタンは自分のユーザー名を再入力するまで無効化しておく。
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _usernameController = TextEditingController();
  bool _deleting = false;
  String? _errorText;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _handleDelete(String expectedUsername) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _deleting = true;
      _errorText = null;
    });

    try {
      final response = await supabase.functions.invoke('delete_account');
      if (response.status != 200) {
        throw Exception(response.data?['error'] ?? 'status ${response.status}');
      }

      await supabase.auth.signOut();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = l10n.deleteAccountError('$e'));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.settingsDeleteAccountLabel)),
        body: Center(child: Text(l10n.profileSignedOutMessage)),
      );
    }

    final profileAsync = ref.watch(profileProvider(currentUser.id));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsDeleteAccountLabel)),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(l10n.profileLoadError('$error'))),
        data: (profile) {
          final username = (profile['username'] as String?) ?? '';

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.deleteAccountWarningTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.red[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(l10n.deleteAccountWarningBody, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                Text(
                  l10n.deleteAccountConfirmInstructions(username),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.deleteAccountUsernameFieldLabel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorText!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (_deleting || _usernameController.text != username || username.isEmpty)
                      ? null
                      : () => _handleDelete(username),
                  child: _deleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(l10n.deleteAccountButton),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
