import 'package:flutter/material.dart';
import 'package:renga/l10n/gen/app_localizations.dart';

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
MaterialColor intellectBadgeColor(IntellectBadgeTier tier) {
  return switch (tier) {
    IntellectBadgeTier.top25 => Colors.teal,
    IntellectBadgeTier.top10 => Colors.blue,
    IntellectBadgeTier.top5 => Colors.indigo,
    IntellectBadgeTier.top1 => Colors.deepPurple,
  };
}

/// バッジ段階に応じた説明文を取得する。
String _getDescriptionKey(IntellectBadgeTier tier) {
  return switch (tier) {
    IntellectBadgeTier.top25 => 'intellect_badge_top25_description',
    IntellectBadgeTier.top10 => 'intellect_badge_top10_description',
    IntellectBadgeTier.top5 => 'intellect_badge_top5_description',
    IntellectBadgeTier.top1 => 'intellect_badge_top1_description',
  };
}

/// design/product.md 3.3節の知能バッジ表示用Widget。
/// タップ可能にしており、タップ時にボトムシートで詳細説明を表示する。
///
/// パーセンタイルが上位25%未満（バッジ対象外）の場合は何も表示しない。
/// フィード（`feed_page.dart`）とプロフィール（`profile_page.dart`）の両方から再利用する。
class IntellectBadge extends StatelessWidget {
  const IntellectBadge({super.key, required this.percentile});

  final num? percentile;

  void _showBadgeDetailsBottomSheet(BuildContext context, IntellectBadgeTier tier) {
    final l10n = AppLocalizations.of(context);
    final color = intellectBadgeColor(tier);
    final descriptionKey = _getDescriptionKey(tier);
    final description = _getLocalizedDescription(l10n, descriptionKey);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // バッジアイコン（色付きの円形）
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(
                    Icons.verified,
                    color: color,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                // バッジタイトル
                Text(
                  intellectBadgeLabel(tier),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // 説明文
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // 閉じるボタン
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('閉じる'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getLocalizedDescription(AppLocalizations l10n, String key) {
    return switch (key) {
      'intellect_badge_top25_description' => l10n.intellect_badge_top25_description,
      'intellect_badge_top10_description' => l10n.intellect_badge_top10_description,
      'intellect_badge_top5_description' => l10n.intellect_badge_top5_description,
      'intellect_badge_top1_description' => l10n.intellect_badge_top1_description,
      _ => 'Unknown badge',
    };
  }

  @override
  Widget build(BuildContext context) {
    final tier = intellectBadgeTierOf(percentile);
    if (tier == null) return const SizedBox.shrink();

    final color = intellectBadgeColor(tier);
    return GestureDetector(
      onTap: () => _showBadgeDetailsBottomSheet(context, tier),
      child: Chip(
        label: Text(intellectBadgeLabel(tier)),
        labelStyle: TextStyle(fontSize: 11, color: color.shade900),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        padding: const EdgeInsets.symmetric(vertical: 0),
        backgroundColor: color.withValues(alpha: 0.15),
        side: BorderSide(color: color),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
