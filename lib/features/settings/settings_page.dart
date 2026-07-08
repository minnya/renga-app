import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../core/auth_state.dart';
import '../../core/locale_controller.dart';
import '../../core/supabase_client.dart';
import '../../core/theme_mode_controller.dart';
import '../../l10n/gen/app_localizations.dart';
import '../feed/feed_controller.dart';

const _kNotificationEnabledKey = 'notifications_enabled';

/// design/product.md 3.11節「Settings（設定）画面」。
///
/// アカウント、通知、表示設定（レイヤーフィルター、テーマモード）、表示言語の各セクションを実装。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final localization = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localization.settingsAppBarTitle),
      ),
      body: ListView(
        children: [
          // セクション1: アカウント
          _AccountSection(user: currentUser),
          const Divider(height: 24),

          // セクション2: 通知
          const _NotificationSection(),
          const Divider(height: 24),

          // セクション3: 表示設定
          const _DisplaySettingsSection(),
          const Divider(height: 24),

          // セクション4: 表示言語
          const _LanguageSection(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// セクション1: アカウント（ログイン中のメール表示、ログアウトボタン）
class _AccountSection extends ConsumerWidget {
  final User? user;

  const _AccountSection({required this.user});

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
          const SizedBox(height: 12),
          // メールアドレス表示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.settingsEmailLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? 'Not logged in',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ログアウトボタン
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

/// セクション2: 通知（プッシュ通知ON/OFF）
class _NotificationSection extends ConsumerWidget {
  const _NotificationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // SharedPreferencesで保存された通知設定を読み込む
    // (既存のFCMトークン登録処理に合わせて、ローカルON/OFF値のみ保存する想定)
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

/// セクション3: 表示設定（レイヤーフィルター、テーマモード）
class _DisplaySettingsSection extends ConsumerWidget {
  const _DisplaySettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currentFilter = ref.watch(layerFilterProvider);
    final currentThemeMode = ref.watch(themeModeProvider);

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
          // レイヤーフィルター設定
          _buildSettingItem(
            context: context,
            title: localization.settingsLayerFilterLabel,
            child: _buildLayerFilterDropdown(ref, currentFilter),
          ),
          const SizedBox(height: 12),
          // テーマモード設定
          _buildSettingItem(
            context: context,
            title: localization.settingsThemeModeLabel,
            child: _buildThemeModeDropdown(ref, currentThemeMode),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerFilterDropdown(WidgetRef ref, LayerFilter currentFilter) {
    return Consumer(builder: (context, ref, _) {
      final localization = AppLocalizations.of(context);
      return DropdownButton<LayerFilter>(
        isExpanded: true,
        value: currentFilter,
        items: [
          DropdownMenuItem(
            value: LayerFilter.all,
            child: Text(localization.feedFilterAll),
          ),
          DropdownMenuItem(
            value: LayerFilter.top25,
            child: Text(localization.feedFilterTop25),
          ),
          DropdownMenuItem(
            value: LayerFilter.top5,
            child: Text(localization.feedFilterTop5),
          ),
        ],
        onChanged: (value) async {
          if (value != null) {
            await ref.read(layerFilterProvider.notifier).select(value);
          }
        },
      );
    });
  }

  Widget _buildThemeModeDropdown(WidgetRef ref, ThemeMode currentThemeMode) {
    return Consumer(builder: (context, ref, _) {
      final localization = AppLocalizations.of(context);
      return DropdownButton<ThemeMode>(
        isExpanded: true,
        value: currentThemeMode,
        items: [
          DropdownMenuItem(
            value: ThemeMode.light,
            child: Text(localization.settingsThemeModeLight),
          ),
          DropdownMenuItem(
            value: ThemeMode.dark,
            child: Text(localization.settingsThemeModeDark),
          ),
          DropdownMenuItem(
            value: ThemeMode.system,
            child: Text(localization.settingsThemeModeSystem),
          ),
        ],
        onChanged: (value) async {
          if (value != null) {
            await ref.read(themeModeProvider.notifier).setThemeMode(value);
          }
        },
      );
    });
  }

  Widget _buildSettingItem({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// セクション4: 表示言語（英語/日本語/端末追従）
class _LanguageSection extends ConsumerWidget {
  const _LanguageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localization = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currentLocale = ref.watch(localeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localization.settingsLanguageSectionTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.settingsLanguageLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButton<Locale?>(
                  isExpanded: true,
                  value: currentLocale,
                  items: [
                    DropdownMenuItem<Locale?>(
                      value: null,
                      child: Text(localization.settingsLanguageSystem),
                    ),
                    DropdownMenuItem<Locale?>(
                      value: const Locale('en'),
                      child: Text(localization.settingsLanguageEnglish),
                    ),
                    DropdownMenuItem<Locale?>(
                      value: const Locale('ja'),
                      child: Text(localization.settingsLanguageJapanese),
                    ),
                  ],
                  onChanged: (value) async {
                    await ref.read(localeProvider.notifier).setLocale(value);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
