import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/weight_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// График шагов (BarChart, `fl_chart`).
///
/// Столбцы — Signal Cobalt. Touch-колбэк: тап по столбцу открывает карточку
/// метрики для этой даты (Фаза 3, секция 6).
class StepsChart extends StatelessWidget {
  final List<StepsDay> stepsData;
  final bool isLoading;
  final void Function(StepsDay tapped)? onTapBar;

  const StepsChart({
    super.key,
    required this.stepsData,
    required this.isLoading,
    this.onTapBar,
  });

  @override
  Widget build(BuildContext context) {
    return ChartCard(
      title: 'Шаги',
      isLoading: isLoading,
      isEmpty: stepsData.isEmpty,
      child: _buildChart(),
    );
  }

  Widget _buildChart() {
    if (stepsData.isEmpty) return const SizedBox.shrink();

    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _gridInterval,
          getDrawingHorizontalLine: (value) =>
              const FlLine(color: CMColors.outline, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: _gridInterval,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: CMFonts.caption(size: 10, color: CMColors.noise),
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
                if (idx < 0 || idx >= stepsData.length) {
                  return const SizedBox.shrink();
                }
                final d = stepsData[idx].date.value;
                return Padding(
                  padding: const EdgeInsets.only(top: CMSpacing.sp1),
                  child: Text(
                    '${d.day}.${d.month}',
                    style: CMFonts.caption(size: 10, color: CMColors.noise),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex >= stepsData.length) return null;
              final d = stepsData[groupIndex].date.value;
              return BarTooltipItem(
                '${d.day}.${d.month}\n${rod.toY.toInt()} шагов',
                CMFonts.caption(size: 11, color: CMColors.ink),
              );
            },
          ),
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response != null && response.spot != null) {
              final idx = response.spot!.touchedBarGroupIndex;
              if (idx >= 0 && idx < stepsData.length) {
                onTapBar?.call(stepsData[idx]);
              }
            }
          },
        ),
        barGroups: stepsData.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.steps.toDouble(),
                width: 12,
                color: CMColors.signal,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(CMRadius.sm),
                  topRight: Radius.circular(CMRadius.sm),
                ),
              ),
            ],
          );
        }).toList(),
        maxY: _maxY,
      ),
    );
  }

  double get _gridInterval {
    if (stepsData.isEmpty) return 1000;
    final maxSteps = stepsData.map((e) => e.steps).reduce((a, b) => a > b ? a : b);
    if (maxSteps <= 0) return 1000;
    return (maxSteps / 4).ceilToDouble();
  }

  double get _maxY {
    if (stepsData.isEmpty) return 100;
    final maxSteps = stepsData.map((e) => e.steps).reduce((a, b) => a > b ? a : b);
    return maxSteps * 1.15;
  }
}