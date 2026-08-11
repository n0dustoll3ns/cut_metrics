import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

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
      child: _buildChart(),
    );
  }

  Widget _buildChart() {
    if (weightData.isEmpty) return const SizedBox.shrink();

    return LineChart(
      LineChartData(
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
                value.toStringAsFixed(1),
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
                if (idx < 0 || idx >= weightData.length) {
                  return const SizedBox.shrink();
                }
                final d = weightData[idx].date.value;
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
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.spotIndex;
                if (idx >= weightData.length) return null;
                final date = weightData[idx].date.value;
                return LineTooltipItem(
                  '${date.day}.${date.month}\n${spot.y.toStringAsFixed(1)} кг',
                  CMFonts.caption(size: 11, color: CMColors.ink),
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
              color: CMColors.signal,
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
            color: CMColors.noiseLight,
            barWidth: 1,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(radius: 3.5, color: CMColors.noise),
            ),
          ),
        ],
        minY: _minY,
        maxY: _maxY,
      ),
    );
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: CMFonts.heading(size: 16)),
            const SizedBox(height: CMSpacing.sp4),
            SizedBox(
              height: 180,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : isEmpty
                      ? Center(
                          child: Text(
                            'Нет данных',
                            style: CMFonts.body(size: 14, color: CMColors.noise),
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
