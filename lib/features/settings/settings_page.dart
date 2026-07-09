import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase_client.dart';
import '../../l10n/gen/app_localizations.dart';

const _kNotificationEnabledKey = 'notifications_enabled';

/// design/product.md 3.11節「Settings（設定）画面」。
///
/// Settings画面自体は**設定項目への遷移リストのみ**を表示し、実際の値の変更UI
/// （フォーム入力・選択肢の確定操作）は各サブページに委ねる。例外は「通知のON/OFF」
/// のようなその場で完結する単純なトグルのみで、これは従来どおり画面内で直接切り替える。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localization = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.settingsAppBarTitle),
      ),
      body: ListView(
        children: [
          const _AccountSection(),
          const Divider(height: 24),
          const _NotificationSection(),
          const Divider(height: 24),
          const _DisplaySettingsSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// セクション1: アカウント（各サブページへの導線、ログアウトボタン）
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localization.settingsAccountSectionTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          // design/product.md 3.11節: メールアドレス自体はここには表示せず、
          // 専用サブページ（/settings/email）でのみ確認できるようにする。
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localization.settingsEmailLabel),
            subtitle: Text(localization.settingsEmailRowSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/email'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localization.profileEditProfileButton),
            subtitle: Text(localization.settingsProfileRowSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/profile'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localization.settingsPasswordChangeLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/password'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              localization.settingsDeleteAccountLabel,
              style: TextStyle(color: Colors.red[600]),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.red[600]),
            onTap: () => context.push('/settings/delete-account'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showLogoutConfirmDialog(context, ref),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
              ),
              child: Text(localization.settingsLogoutButton),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmDialog(BuildContext context, WidgetRef ref) {
    final localization = AppLocalizations.of(context);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.settingsLogoutConfirmTitle),
        content: Text(localization.settingsLogoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localization.settingsCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // ログアウト処理。go_routerの認証redirectが自動的に/loginへ飛ばす。
              await supabase.auth.signOut();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red[600]),
            child: Text(localization.settingsLogout),
          ),
        ],
      ),
    );
  }
}

/// セクション2: 通知（プッシュ通知ON/OFF）。単純なトグルのため画面内で直接切り替える。
class _NotificationSection extends ConsumerWidget {
  const _NotificationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return StatefulBuilder(
      builder: (context, setState) {
        return FutureBuilder<bool>(
          future: _loadNotificationEnabled(),
          builder: (context, snapshot) {
            final isNotificationEnabled = snapshot.data ?? true;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localization.settingsNotificationSectionTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(localization.settingsNotificationToggle),
                    subtitle: Text(
                      localization.settingsNotificationDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: isNotificationEnabled,
                    onChanged: (value) async {
                      await _setNotificationEnabled(value);
                      setState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _loadNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kNotificationEnabledKey) ?? true;
  }

  Future<void> _setNotificationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotificationEnabledKey, enabled);
    // TODO: FCM token登録/削除処理をここで呼び出す
    // (lib/core/fcm_service.dartの既存の仕組みを活かす想定)
  }
}

/// セクション3: 表示設定（表示設定サブページ）・表示言語（言語サブページ）への導線。
/// design/product.md 3.11節: 選択肢一覧はSettings画面には埋め込まず、専用サブページで
/// 選ぶと即座に確定して前の画面へ戻る。
class _DisplaySettingsSection extends ConsumerWidget {
  const _DisplaySettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localization.settingsDisplaySectionTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localization.settingsDisplaySectionTitle),
            subtitle: Text(localization.settingsLayerFilterLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/display'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localization.settingsLanguageSectionTitle),
            subtitle: Text(localization.settingsLanguageLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/language'),
          ),
        ],
      ),
    );
  }
}
