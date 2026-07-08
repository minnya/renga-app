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
/// 選択肢から1つを選ぶ項目（レイヤーフィルター・テーマ・言語）はボトムシートで編集する
/// （画面内にドロップダウンを直接置かない）。通知ON/OFFは単純なトグルのため画面内で直接切り替える。
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
          _AccountSection(user: currentUser),
          const Divider(height: 24),
          const _NotificationSection(),
          const Divider(height: 24),
          const _DisplaySettingsSection(),
          const Divider(height: 24),
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

/// 単一選択肢を選ぶための共通ボトムシート。
/// design/system.md 9章「設定・編集系UIの方針」。intellect_badge.dartと同じ角丸の意匠。
Future<void> _showChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required T currentValue,
  required List<(T, String)> options,
  required ValueChanged<T> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              RadioGroup<T>(
                groupValue: currentValue,
                onChanged: (value) {
                  if (value != null) {
                    onSelected(value);
                  }
                  Navigator.pop(sheetContext);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options)
                      RadioListTile<T>(
                        value: option.$1,
                        title: Text(option.$2),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// セクション3: 表示設定（レイヤーフィルター、テーマモード）。ボトムシートで選択する。
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localization.settingsLayerFilterLabel),
            subtitle: Text(_layerFilterLabel(currentFilter, localization)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChoiceSheet<LayerFilter>(
              context: context,
              title: localization.settingsLayerFilterLabel,
              currentValue: currentFilter,
              options: [
                (LayerFilter.all, localization.feedFilterAll),
                (LayerFilter.top25, localization.feedFilterTop25),
                (LayerFilter.top5, localization.feedFilterTop5),
              ],
              onSelected: (value) => ref.read(layerFilterProvider.notifier).select(value),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localization.settingsThemeModeLabel),
            subtitle: Text(_themeModeLabel(currentThemeMode, localization)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChoiceSheet<ThemeMode>(
              context: context,
              title: localization.settingsThemeModeLabel,
              currentValue: currentThemeMode,
              options: [
                (ThemeMode.light, localization.settingsThemeModeLight),
                (ThemeMode.dark, localization.settingsThemeModeDark),
                (ThemeMode.system, localization.settingsThemeModeSystem),
              ],
              onSelected: (value) => ref.read(themeModeProvider.notifier).setThemeMode(value),
            ),
          ),
        ],
      ),
    );
  }

  String _layerFilterLabel(LayerFilter filter, AppLocalizations l10n) => switch (filter) {
        LayerFilter.all => l10n.feedFilterAll,
        LayerFilter.top25 => l10n.feedFilterTop25,
        LayerFilter.top5 => l10n.feedFilterTop5,
      };

  String _themeModeLabel(ThemeMode mode, AppLocalizations l10n) => switch (mode) {
        ThemeMode.light => l10n.settingsThemeModeLight,
        ThemeMode.dark => l10n.settingsThemeModeDark,
        ThemeMode.system => l10n.settingsThemeModeSystem,
      };
}

/// セクション4: 表示言語（英語/日本語/端末追従）。ボトムシートで選択する。
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(localization.settingsLanguageLabel),
            subtitle: Text(_localeLabel(currentLocale, localization)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showChoiceSheet<Locale?>(
              context: context,
              title: localization.settingsLanguageLabel,
              currentValue: currentLocale,
              options: [
                (null, localization.settingsLanguageSystem),
                (const Locale('en'), localization.settingsLanguageEnglish),
                (const Locale('ja'), localization.settingsLanguageJapanese),
              ],
              onSelected: (value) => ref.read(localeProvider.notifier).setLocale(value),
            ),
          ),
        ],
      ),
    );
  }

  String _localeLabel(Locale? locale, AppLocalizations l10n) {
    if (locale == null) return l10n.settingsLanguageSystem;
    return switch (locale.languageCode) {
      'ja' => l10n.settingsLanguageJapanese,
      _ => l10n.settingsLanguageEnglish,
    };
  }
}
