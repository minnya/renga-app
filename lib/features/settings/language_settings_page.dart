import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale_controller.dart';
import '../../l10n/gen/app_localizations.dart';

/// design/product.md 3.11節「Settings（設定）画面」の表示言語サブページ。
///
/// 表示設定サブページと同様に、選択肢一覧（[RadioListTile]）から1つを選ぶと
/// 即座に確定して別途の保存ボタンは持たない。
class LanguageSettingsPage extends ConsumerWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currentLocale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsLanguageSectionTitle)),
      body: RadioGroup<Locale?>(
        groupValue: currentLocale,
        onChanged: (value) {
          ref.read(localeProvider.notifier).setLocale(value);
        },
        child: Column(
          children: [
            RadioListTile<Locale?>(
              value: null,
              title: Text(l10n.settingsLanguageSystem),
            ),
            RadioListTile<Locale?>(
              value: const Locale('en'),
              title: Text(l10n.settingsLanguageEnglish),
            ),
            RadioListTile<Locale?>(
              value: const Locale('ja'),
              title: Text(l10n.settingsLanguageJapanese),
            ),
          ],
        ),
      ),
    );
  }
}
