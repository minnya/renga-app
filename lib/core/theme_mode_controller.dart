import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// design/product.md 3.11節「Settings（設定）画面」: テーマ選択を管理するProvider。
///
/// ライト/ダーク/端末設定に従うの3つのモードをSharedPreferencesで永続化し、
/// `lib/main.dart`の`MaterialApp.router`の`themeMode`パラメータに渡す。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // 非同期でローカル値を読み込む（初期化中は ThemeMode.system を返す）。
    // ignore: discarded_futures
    _loadInitial();
    return ThemeMode.system;
  }

  Future<void> _loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getString(_kThemeModePrefsKey) ?? 'system';
    state = _themeModeFromString(savedValue);
  }

  /// ユーザーがテーマモードを変更した際に呼ぶ。
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModePrefsKey, _themeModeToString(mode));
  }

  static String _themeModeToString(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  static ThemeMode _themeModeFromString(String value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

const _kThemeModePrefsKey = 'theme_mode';

/// テーマモードの選択状態を管理するProvider。
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
