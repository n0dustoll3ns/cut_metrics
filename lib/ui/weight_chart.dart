import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/ui/months.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// График веса + EMA с осью дат Фазы 6 (A3, `test_report_26-09-02.md`):
///
/// - Обычный день — только число («7»), Space Mono 10px, Noise Grey.
/// - Граница месяца — «1 АВГ» (число + 3-буквенный месяц uppercase, Ink
///   Muted). Показывается ВСЕГДА, даже вне шага прореживания — вытесняет
///   ближайшую обычную метку.
/// - Прореживание: не более ~8 меток (шаг = ceil(точек / 7)).
/// - Граница месяца подсвечивается тонкой вертикальной линией сетки
///   (outline, 1px).
/// - Тултип по тапу — полная дата «17 июл» + значение.
///
/// Общий для «Сегодня» (30 дн) и «Тренда» (7/30/90 дн). Цвета — роли
/// текущей темы (светлая/тёмная).
class WeightChart extends StatelessWidget {
  final List<WeightDay> weightData;
  final List<WeightDay> emaData;
  final bool isLoading;
  final void Function(WeightDay tapped)? onTapPoint;

  const WeightChart({
    super.key,
    required this.weightData,
    required this.emaData,
    required this.isLoading,
    this.onTapPoint,
  });

  @override
  Widget build(BuildContext context) {
    return ChartCard(
      title: 'Вес и тренд',
      isLoading: isLoading,
      isEmpty: weightData.isEmpty,
      child: _buildChart(context),
    );
  }

  Widget _buildChart(BuildContext context) {
    if (weightData.isEmpty) return const SizedBox.shrink();
    final colors = context.cmColors;
    final labels = _dateLabels();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          verticalInterval: 1,
          horizontalInterval: _gridInterval,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: colors.outline, strokeWidth: 1),
          // Вертикальная линия — только на границе месяца (A3), остальные
          // индексы прозрачны.
          getDrawingVerticalLine: (value) {
            final idx = value.toInt();
            final isMonthBoundary = idx >= 0 &&
                idx < weightData.length &&
                weightData[idx].date.value.day == 1;
            return FlLine(
              color: isMonthBoundary ? colors.outline : Colors.transparent,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: _gridInterval,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: CMFonts.caption(size: 10, color: colors.noise),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                final label = labels[idx];
                if (label == null) return const SizedBox.shrink();
                final isMonthBoundary = weightData[idx].date.value.day == 1;
                return Padding(
                  padding: const EdgeInsets.only(top: CMSpacing.sp1),
                  child: Text(
                    label,
                    style: isMonthBoundary
                        ? CMFonts.caption(size: 10, color: colors.inkMuted)
                        : CMFonts.caption(size: 10, color: colors.noise),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.spotIndex;
                if (idx >= weightData.length) return null;
                final date = weightData[idx].date.value;
                return LineTooltipItem(
                  '${date.day} ${kMonthsShort[date.month - 1]}\n'
                  '${spot.y.toStringAsFixed(1)} кг',
                  CMFonts.caption(size: 11, color: colors.ink),
                );
              }).toList();
            },
          ),
          touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
            if (event is FlTapUpEvent && response != null) {
              final spots = response.lineBarSpots;
              if (spots != null && spots.isNotEmpty) {
                final idx = spots.first.spotIndex;
                if (idx >= 0 && idx < weightData.length) {
                  onTapPoint?.call(weightData[idx]);
                }
              }
            }
          },
        ),
        lineBarsData: [
          if (emaData.isNotEmpty)
            LineChartBarData(
              spots: emaData
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value.weight))
                  .toList(),
              isCurved: true,
              color: colors.signal,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
            ),
          LineChartBarData(
            spots: weightData
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value.weight))
                .toList(),
            isCurved: false,
            color: colors.noiseLight,
            barWidth: 1,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(radius: 3.5, color: colors.noise),
            ),
          ),
        ],
        minY: _minY,
        maxY: _maxY,
      ),
    );
  }

  /// Метки нижней оси: индекс → текст (A3).
  ///
  /// 1. Базовый набор: каждые `ceil(n / 7)` индексов (≤8 меток на ширину).
  /// 2. Граница месяца (день 1) — метка «1 АВГ» всегда; ближайшая обычная
  ///    метка вытесняется, чтобы соседние надписи не слипались.
  Map<int, String> _dateLabels() {
    final n = weightData.length;
    if (n == 0) return {};

    final step = (n / 7).ceil().clamp(1, n);
    final regular = <int>{};
    for (var i = 0; i < n; i += step) {
      regular.add(i);
    }

    final labels = <int, String>{};
    for (var i = 0; i < n; i++) {
      final d = weightData[i].date.value;
      if (d.day != 1) continue;
      labels[i] = '1 ${kMonthsShort[d.month - 1].toUpperCase()}';
      // Вытесняем ближайшую обычную метку (предыдущую, иначе следующую).
      if (regular.contains(i - 1)) {
        regular.remove(i - 1);
      } else if (regular.contains(i + 1)) {
        regular.remove(i + 1);
      }
      regular.remove(i);
    }
    for (final i in regular) {
      if (!labels.containsKey(i)) {
        labels[i] = '${weightData[i].date.value.day}';
      }
    }
    return labels;
  }

  double get _gridInterval {
    final range = _maxY - _minY;
    return range <= 0 ? 1.0 : (range / 4).ceilToDouble();
  }

  double get _minY {
    if (weightData.isEmpty) return 0;
    final minW = weightData.map((e) => e.weight).reduce((a, b) => a < b ? a : b);
    final maxW = weightData.map((e) => e.weight).reduce((a, b) => a > b ? a : b);
    return minW - (maxW - minW) * 0.1 - 1;
  }

  double get _maxY {
    if (weightData.isEmpty) return 100;
    final minW = weightData.map((e) => e.weight).reduce((a, b) => a < b ? a : b);
    final maxW = weightData.map((e) => e.weight).reduce((a, b) => a > b ? a : b);
    return maxW + (maxW - minW) * 0.1 + 1;
  }
}

class ChartCard extends StatelessWidget {
  final String title;
  final bool isLoading;
  final bool isEmpty;
  final Widget child;

  const ChartCard({
    super.key,
    required this.title,
    required this.isLoading,
    required this.isEmpty,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: CMFonts.heading(size: 16, color: colors.ink)),
            const SizedBox(height: CMSpacing.sp4),
            SizedBox(
              height: 180,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : isEmpty
                      ? Center(
                          child: Text(
                            'Нет данных',
                            style: CMFonts.body(size: 14, color: colors.noise),
                          ),
                        )
                      : child,
            ),
          ],
        ),
      ),
    );
  }
}
