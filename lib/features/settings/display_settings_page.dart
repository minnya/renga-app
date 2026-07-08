import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme_mode_controller.dart';
import '../../l10n/gen/app_localizations.dart';
import '../feed/feed_controller.dart';

/// design/product.md 3.11節「Settings（設定）画面」の表示設定サブページ。
///
/// レイヤーフィルターの既定値、テーマ選択を、それぞれ選択肢一覧（[RadioListTile]）として
/// このページ上に表示する。選択すると即座に確定し、別途の保存ボタンは持たない。
class DisplaySettingsPage extends ConsumerWidget {
  const DisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currentFilter = ref.watch(layerFilterProvider);
    final currentThemeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsDisplaySectionTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.settingsLayerFilterLabel,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          RadioGroup<LayerFilter>(
            groupValue: currentFilter,
            onChanged: (value) {
              if (value != null) {
                ref.read(layerFilterProvider.notifier).select(value);
              }
            },
            child: Column(
              children: [
                RadioListTile<LayerFilter>(
                  value: LayerFilter.all,
                  title: Text(l10n.feedFilterAll),
                ),
                RadioListTile<LayerFilter>(
                  value: LayerFilter.top25,
                  title: Text(l10n.feedFilterTop25),
                ),
                RadioListTile<LayerFilter>(
                  value: LayerFilter.top5,
                  title: Text(l10n.feedFilterTop5),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.settingsThemeModeLabel,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          RadioGroup<ThemeMode>(
            groupValue: currentThemeMode,
            onChanged: (value) {
              if (value != null) {
                ref.read(themeModeProvider.notifier).setThemeMode(value);
              }
            },
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text(l10n.settingsThemeModeLight),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text(l10n.settingsThemeModeDark),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text(l10n.settingsThemeModeSystem),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
