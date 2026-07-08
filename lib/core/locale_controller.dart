import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// design/product.md 3.11節「Settings（設定）画面」: 表示言語（ロケール）を管理するProvider。
///
/// null（端末言語追従）、Locale('en')、Locale('ja')の3つの状態をSharedPreferencesで永続化し、
/// `lib/main.dart`の`MaterialApp.router`の`locale`パラメータに渡す。
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    // 非同期でローカル値を読み込む（初期化中は null = 端末追従を返す）。
    // ignore: discarded_futures
    _loadInitial();
    return null;
  }

  Future<void> _loadInitial() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getString(_kLocalePrefsKey);
    state = _localeFromString(savedValue);
  }

  /// ユーザーが表示言語を変更した際に呼ぶ。
  /// - null: 端末言語設定に追従
  /// - Locale('en'): English
  /// - Locale('ja'): 日本語
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_kLocalePrefsKey);
    } else {
      await prefs.setString(_kLocalePrefsKey, _localeToString(locale));
    }
  }

  static String _localeToString(Locale locale) => locale.languageCode;

  static Locale? _localeFromString(String? value) => switch (value) {
    'en' => const Locale('en'),
    'ja' => const Locale('ja'),
    _ => null,
  };
}

const _kLocalePrefsKey = 'locale_override';

/// 表示言語（ロケール）の選択状態を管理するProvider。
final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
