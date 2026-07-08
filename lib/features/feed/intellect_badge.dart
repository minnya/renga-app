import 'package:flutter/material.dart';

/// design/product.md 3.3節「知能バッジとレイヤーフィルター」の知能バッジ段階。
///
/// 上位25%未満（一般層）はバッジなし＝マイナス表示はしない、という設計思想を守るため
/// enumには含めない（`intellectBadgeTierOf` が `null` を返す）。
enum IntellectBadgeTier { top25, top10, top5, top1 }

/// パーセンタイル（値が小さいほど上位。例: 上位5% → `intellect_percentile <= 5`）から
/// 表示すべきバッジ段階を判定する。上位25%未満は `null`（バッジなし＝一般層）。
IntellectBadgeTier? intellectBadgeTierOf(num? percentile) {
  if (percentile == null) return null;
  if (percentile <= 1) return IntellectBadgeTier.top1;
  if (percentile <= 5) return IntellectBadgeTier.top5;
  if (percentile <= 10) return IntellectBadgeTier.top10;
  if (percentile <= 25) return IntellectBadgeTier.top25;
  return null;
}

/// バッジ段階ごとの表示ラベル。
String intellectBadgeLabel(IntellectBadgeTier tier) {
  return switch (tier) {
    IntellectBadgeTier.top25 => '上位25%',
    IntellectBadgeTier.top10 => '上位10%',
    IntellectBadgeTier.top5 => '上位5%',
    IntellectBadgeTier.top1 => '上位1%',
  };
}

/// バッジ段階ごとの表示色。上位になるほど寒色〜彩度の高い配色にし、
/// design/product.md 5章「Intellect=cool系グラデーション」の方針に沿う。
Color intellectBadgeColor(IntellectBadgeTier tier) {
  return switch (tier) {
    IntellectBadgeTier.top25 => Colors.teal,
    IntellectBadgeTier.top10 => Colors.blue,
    IntellectBadgeTier.top5 => Colors.indigo,
    IntellectBadgeTier.top1 => Colors.deepPurple,
  };
}

/// design/product.md 3.3節の知能バッジ表示用Widget。
///
/// パーセンタイルが上位25%未満（バッジ対象外）の場合は何も表示しない。
/// フィード（`feed_page.dart`）とプロフィール（`profile_page.dart`）の両方から再利用する。
class IntellectBadge extends StatelessWidget {
  const IntellectBadge({super.key, required this.percentile});

  final num? percentile;

  @override
  Widget build(BuildContext context) {
    final tier = intellectBadgeTierOf(percentile);
    if (tier == null) return const SizedBox.shrink();

    final color = intellectBadgeColor(tier);
    return Chip(
      label: Text(intellectBadgeLabel(tier)),
      labelStyle: TextStyle(fontSize: 11, color: color.shade900),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
