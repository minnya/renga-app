// プロフィール画面のIQ(Intellect)/Influence 平均比較・前日比表示用のフォーマットヘルパー。
//
// design/system.md 2章「平均値・日次推移（プロフィール画面の比較表示）」・
// design/product.md 3.10節「平均値との比較・前日比の表示」に対応する。

/// 差分を符号付き整数文字列にフォーマットする（例: 15 → "+15"、-8 → "-8"、0 → "±0"）。
String formatSignedDiff(num diff) {
  final rounded = diff.round();
  if (rounded > 0) return '+$rounded';
  if (rounded < 0) return '$rounded';
  return '±0';
}
