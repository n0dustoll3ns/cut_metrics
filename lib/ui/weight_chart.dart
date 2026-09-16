import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/ui/chart_date_axis.dart';
import 'package:cut_metrics/ui/months.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// График веса + EMA с осью дат Фазы 6 (A3, `test_report_26-09-02.md`).
///
/// Календарная ось (2026-09-16): слот на каждый день от первой до последней
/// даты с данными; дни без взвешивания — пустые слоты (`FlSpot.nullSpot`
/// разрывает линию и точку) — на графике видны «пустоты». Тап/тултип на
/// пустом слоте не срабатывают.
///
/// - Обычный день — только число («7»), Space Mono 10px, Noise Grey.
/// - Граница месяца — «1 АВГ» (число + 3-буквенный месяц uppercase, Ink
/// Muted). Показывается ВСЕГДА, даже вне шага прореживания — вытесняет
/// ближайшую обычную метку.
/// - Прореживание: не более ~8 меток (шаг = ceil(точек / 7)).
/// - Граница месяца подсвечивается тонкой вертикальной линией сетки
/// (outline, 1px).
/// - Тултип по тапу — полная дата «17 июл» + значение; фон surface0 с
/// рамкой outline (единый стиль с графиком баланса), у краёв карточки
/// не вылезает (`fitInsideHorizontally/Vertically`, 2026-09-16).
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

    // Календарная ось: слот на каждый день между первой и последней датой
    // с данными; дни без взвешивания — пустые слоты («пустоты»).
    final dates = calendarDatesBetween(
      weightData.first.date.value,
      weightData.last.date.value,
    );
    final weightByDate = {for (final d in weightData) d.date: d};
    final emaByDate = {for (final d in emaData) d.date: d};

    final axis = computeChartDateAxis(dates);
    final labels = axis.labels;

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
            final isMonthBoundary = axis.monthBoundaries.contains(value.toInt());
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
                final isMonthBoundary = axis.monthBoundaries.contains(idx);
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
            getTooltipColor: (_) => colors.surface0,
            tooltipBorder: BorderSide(color: colors.outline),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.round(); // слот, не индекс массива (EMA пропускает слоты)
                if (idx < 0 || idx >= dates.length) return null;
                final day = weightByDate[DateKey(dates[idx])];
                if (day == null) return null;
                final date = day.date.value;
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
                final idx = spots.first.x.round();
                if (idx >= 0 && idx < dates.length) {
                  final day = weightByDate[DateKey(dates[idx])];
                  if (day != null) onTapPoint?.call(day);
                }
              }
            }
          },
        ),
        lineBarsData: [
          if (emaData.isNotEmpty)
            LineChartBarData(
              // Короткие пропуски (меньше 5 пустых дней) линия EMA проходит
              // напрямую (слот пропускается), при 5+ пустых днях — разрыв
              // (nullSpot), как в computeEma (правило 2026-09-16).
              spots: _emaSpots(dates, emaByDate),
              isCurved: true,
              color: colors.signal,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: [
              for (var i = 0; i < dates.length; i++)
                weightByDate[DateKey(dates[i])] == null
                  ? FlSpot.nullSpot
                  : FlSpot(i.toDouble(), weightByDate[DateKey(dates[i])]!.weight),
            ],
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

  /// Споты EMA (2026-09-16): точки на днях взвешивания; между точками
  /// с пропуском меньше [RecommendationConfig.emaBreakGapDays] пустых дней
  /// слот пропускается — линия соединяет соседние точки напрямую
  /// (кривая непрерывна); при пропуске 5+ пустых дней добавляется
  /// nullSpot — разрыв серии (согласовано с computeEma).
  List<FlSpot> _emaSpots(List<DateTime> dates, Map<DateKey, WeightDay> emaByDate) {
    final slots = <int>[
      for (var i = 0; i < dates.length; i++)
        if (emaByDate[DateKey(dates[i])] != null) i,
    ];
    final result = <FlSpot>[];
    for (var k = 0; k < slots.length; k++) {
      final i = slots[k];
      result.add(FlSpot(i.toDouble(), emaByDate[DateKey(dates[i])]!.weight));
      final next = k + 1 < slots.length ? slots[k + 1] : null;
      if (next != null && next - i - 1 >= RecommendationConfig.emaBreakGapDays) {
        result.add(FlSpot.nullSpot); // разрыв серии EMA
      }
    }
    return result;
  }

  /// Метки нижней оси — общий хелпер Фазы 6/7 (`chart_date_axis.dart`).

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
