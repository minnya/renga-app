import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../l10n/gen/app_localizations.dart';

/// 推移グラフ1点分のデータ（日付とスコア値）。
///
/// design/system.md 2章「日次推移」。`user_score_history` の1行から作られる。
class ScoreHistoryPoint {
  const ScoreHistoryPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

/// IQ(Intellect)/Influence の推移を折れ線グラフで表示するボトムシートを開く。
///
/// design/product.md 3.10節「推移グラフ」。プロフィール画面でIQ表示・Influence表示をタップすると
/// このシートが開き、`user_score_history` の時系列データと `score_stats` の全ユーザー平均を
/// 基準線として重ねて表示する。
void showScoreHistorySheet(
  BuildContext context, {
  required String title,
  required List<ScoreHistoryPoint> points,
  required double average,
  required Color color,
  required String Function(double value) valueFormatter,
}) {
  final l10n = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (points.length < 2)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text(l10n.profileScoreHistoryEmpty)),
                )
              else
                SizedBox(
                  height: 220,
                  child: _ScoreHistoryChart(
                    points: points,
                    average: average,
                    color: color,
                    valueFormatter: valueFormatter,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(width: 12, height: 2, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    l10n.profileScoreHistoryAverageLegend,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.profileScoreHistoryClose),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ScoreHistoryChart extends StatelessWidget {
  const _ScoreHistoryChart({
    required this.points,
    required this.average,
    required this.color,
    required this.valueFormatter,
  });

  final List<ScoreHistoryPoint> points;
  final double average;
  final Color color;
  final String Function(double value) valueFormatter;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value),
    ];
    final values = [...points.map((p) => p.value), average];
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = ((maxY - minY).abs() * 0.15).clamp(1.0, double.infinity);

    return LineChart(
      LineChartData(
        minY: minY - padding,
        maxY: maxY + padding,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                valueFormatter(value),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (points.length / 4).clamp(1, double.infinity).roundToDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('M/d').format(points[index].date),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: average,
              color: Theme.of(context).colorScheme.outline,
              strokeWidth: 1.5,
              dashArray: [6, 4],
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots
                .map(
                  (spot) => LineTooltipItem(
                    valueFormatter(spot.y),
                    Theme.of(context).textTheme.bodySmall!.copyWith(color: color),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
