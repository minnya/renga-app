import 'package:flutter/material.dart';

/// design/product.md 5章「デザインシステム方針」。
///
/// UIの見た目はInstagram（ライトモード）/ X・Twitter（ダークモード）を参考にし、
/// 独自の作り込みウィジェットは最小限に留めてMaterial 3の`Theme`カスタマイズで再現する。
/// Influence/Intellectの2軸配色はバッジ・スコア表示等のアクセントに限定して使う
/// （UI全体の基調はあくまでX/Instagram寄りの落ち着いた配色）。
class RengaColors {
  RengaColors._();

  /// X/Instagram共通の「単色の鮮やかな青」アクセント（Instagram公式アプリのリンク色に近い）。
  static const Color accent = Color(0xFF0095F6);

  /// design/product.md 3章の2軸配色（バッジ・スコアグラフ等のアクセント専用。背景等には使わない）。
  static const Color influence = Color(0xFFFF7A45);
  static const Color intellect = Color(0xFF3B82F6);

  /// Instagram風ライトモードの背景色（純白ではなくごく僅かにオフホワイト）。
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightDivider = Color(0xFFDBDBDB);

  /// X(Twitter)風ダークモードの背景色（純黒基調）。
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF000000);
  static const Color darkDivider = Color(0xFF2F3336);
}

ThemeData buildRengaLightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: RengaColors.accent,
    brightness: Brightness.light,
  ).copyWith(
    primary: RengaColors.accent,
    secondary: RengaColors.accent,
    surface: RengaColors.lightSurface,
    outline: RengaColors.lightDivider,
  );

  return _buildTheme(colorScheme: colorScheme, scaffoldBackground: RengaColors.lightBackground);
}

ThemeData buildRengaDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: RengaColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: RengaColors.accent,
    secondary: RengaColors.accent,
    surface: RengaColors.darkSurface,
    outline: RengaColors.darkDivider,
  );

  return _buildTheme(colorScheme: colorScheme, scaffoldBackground: RengaColors.darkBackground);
}

ThemeData _buildTheme({required ColorScheme colorScheme, required Color scaffoldBackground}) {
  final isDark = colorScheme.brightness == Brightness.dark;
  final dividerColor = colorScheme.outline;

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    // X/Instagramともにアプリバーは背景に溶け込む単色・フラット・影なしが基本。
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBackground,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    // ボトムナビゲーションはInstagram/X同様、アイコンのみ・ラベル非表示・フラット。
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: scaffoldBackground,
      selectedItemColor: colorScheme.onSurface,
      unselectedItemColor: colorScheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(color: dividerColor, thickness: 0.5, space: 0.5),
    cardTheme: CardThemeData(
      color: scaffoldBackground,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dividerColor),
      ),
    ),
    // ボタンはX/Instagramらしい「角の丸い塗りつぶし」ボタンを基本形にする。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: dividerColor),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark ? const Color(0xFF16181C) : const Color(0xFFEFEFEF),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: colorScheme.onSurface, fontSize: 12),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: colorScheme.primary,
      labelColor: colorScheme.onSurface,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
    ),
    dividerColor: dividerColor,
    splashFactory: InkRipple.splashFactory,
  );
}
