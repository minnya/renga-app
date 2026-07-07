import 'package:flutter/material.dart';

/// design/product.md 4章「カラーパレット」の方針（Influence=暖色系 / Intellect=寒色系）に
/// 沿った暫定トークン。ブランド確定前の仮値で、確定後に差し替える前提。
class RengaColors {
  RengaColors._();

  static const Color influence = Color(0xFFFF7A45);
  static const Color intellect = Color(0xFF3B82F6);
  static const Color seed = Color(0xFF6750A4);
}

ThemeData buildRengaTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: RengaColors.seed),
    useMaterial3: true,
  );
}
