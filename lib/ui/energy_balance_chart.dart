import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/ui/chart_date_axis.dart';
import 'package:cut_metrics/ui/format.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// График энергобаланса — вариант A2 (Фаза 7, B.1 / дизайн-система §05).
///
/// - Один столбец — один день: приход − расход. Дефицит — вниз от нулевой
///   линии (steady), профицит — вверх (alert). День без прихода ИЛИ без
///   расхода — столбца нет (это не ноль, A.4 п.4).
/// - Нулевая линия — ink-muted 1px; целевая линия дефицита — signal 1.5px,
///   пунктир 5–4, подпись «цель −N» (N = вес × темп% × 11, кратно 10).
/// - Ось дат — механика WeightChart A3 (`chart_date_axis.dart`).
/// - Тултип в 2 строки: «17 июл» / «Приход 2 150 · Расход 2 680 · Баланс −530».
/// - Масштаб: ноль, целевая и все балансы всегда в кадре.
/// - Включает столбец «сегодня» (день ещё не завершён — осознанно, A.8).
///
/// Отрицательные столбцы — нативная возможность fl_chart 0.69
/// (`BarChartRodData.fromY → toY`), ось не сдвигалась.
class EnergyBalanceChart extends StatelessWidget {
  /// Дни с приходом И расходом (`DashboardViewModel.balanceData`).
  final List<EnergyBalanceDay> balanceData;

  /// Целевой дефицит, ккал/день (положительное число); `null` — веса нет.
  final double? targetDeficitKcalPerDay;

  /// Дней в диапазоне без данных питания (примечание под графиком).
  final int daysWithoutNutrition;

  final bool isLoading;

  const EnergyBalanceChart({
    super.key,
    required this.balanceData,
    required this.targetDeficitKcalPerDay,
    required this.daysWithoutNutrition,
    required this.isLoading,
  });

  /// Цель, округлённая до 10 (для линии и подписи).
  int? get _targetRounded {
    final t = targetDeficitKcalPerDay;
    if (t == null || t <= 0) return null;
    return (t / 10).round() * 10;
  }

  double get _barWidth {
    final n = balanceData.length;
    if (n <= 7) return 14;
    // ≈ min(14, 0.6 × шаг) при типичной ширине карточки ~320px.
    return (0.6 * 320 / n).clamp(3.0, 14.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Энергобаланс',
                    style: CMFonts.heading(size: 16, color: colors.ink)),
                Text('ккал/день',
                    style: CMFonts.caption(size: 10, color: colors.noise)),
              ],
            ),
            const SizedBox(height: CMSpacing.sp2),
            EnergyLegend(targetRounded: _targetRounded),
            const SizedBox(height: CMSpacing.sp3),
            SizedBox(
              height: 180,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : balanceData.isEmpty
                      ? Center(
                          child: Text(
                            'Нет данных',
                            style: CMFonts.body(size: 14, color: colors.noise),
                          ),
                        )
                      : _buildChart(context),
            ),
            if (daysWithoutNutrition > 0) ...[
              const SizedBox(height: CMSpacing.sp2),
              Text(
                'Дней без данных питания: $daysWithoutNutrition',
                style: CMFonts.caption(size: 10, color: colors.noise),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChart(BuildContext context) {
    final colors = context.cmColors;
    final axis = computeChartDateAxis(
      balanceData.map((e) => e.date.value).toList(),
    );
    final target = _targetRounded;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _maxY,
        minY: _minY,
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: false,
          drawVerticalLine: true,
          verticalInterval: 1,
          getDrawingVerticalLine: (value) => FlLine(
            color: axis.monthBoundaries.contains(value.toInt())
                ? colors.outline
                : Colors.transparent,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                final label = axis.labels[idx];
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
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => colors.surface0,
            tooltipBorder: BorderSide(color: colors.outline),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 280,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final day = balanceData[groupIndex];
              return BarTooltipItem(
                chartTooltipDate(day.date.value),
                CMFonts.caption(size: 10, color: colors.noise),
                children: [
                  TextSpan(
                    text:
                        '\nПриход ${formatThousands(day.intake.calories)} · '
                        'Расход ${formatThousands(day.out.total)} · '
                        'Баланс ${formatSignedKcal(day.balance)}',
                    style: CMFonts.label(size: 11, color: colors.ink),
                  ),
                ],
              );
            },
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(y: 0, color: colors.inkMuted, strokeWidth: 1),
            if (target != null)
              HorizontalLine(
                y: -target.toDouble(),
                color: colors.signal,
                strokeWidth: 1.5,
                dashArray: const [5, 4],
                label: HorizontalLineLabel(
                  labelResolver: (_) => 'цель −${formatThousands(target)}',
                  alignment: Alignment.bottomRight,
                  style: CMFonts.caption(size: 9, color: colors.signal),
                ),
              ),
          ],
        ),
        barGroups: [
          for (var i = 0; i < balanceData.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  fromY: 0,
                  toY: balanceData[i].balance,
                  color: balanceData[i].balance < 0 ? colors.steady : colors.alert,
                  width: _barWidth,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Ноль, цель (−N) и все балансы всегда в кадре (+15% запас).
  double get _minY => _minRaw - _padding;

  double get _maxY => _maxRaw + _padding;

  double get _padding {
    final range = _maxRaw - _minRaw;
    return range <= 0 ? 100.0 : range * 0.15;
  }

  double get _minRaw {
    var min = 0.0;
    final target = _targetRounded;
    if (target != null) min = -target.toDouble();
    for (final b in balanceData) {
      if (b.balance < min) min = b.balance;
    }
    return min;
  }

  double get _maxRaw {
    var max = 0.0;
    for (final b in balanceData) {
      if (b.balance > max) max = b.balance;
    }
    return max;
  }
}

/// Легенда: Дефицит (steady) / Профицит (alert) / Цель −N (signal-пунктир).
class EnergyLegend extends StatelessWidget {
  final int? targetRounded;

  const EnergyLegend({super.key, this.targetRounded});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Wrap(
      spacing: CMSpacing.sp3,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _item(colors.steady, 'Дефицит', solid: true),
        _item(colors.alert, 'Профицит', solid: true),
        if (targetRounded != null)
          _item(
            colors.signal,
            'Цель −${formatThousands(targetRounded!)}',
            solid: false,
          ),
      ],
    );
  }

  Widget _item(Color color, String label, {required bool solid}) {
    return Builder(builder: (context) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (solid)
            Container(width: 10, height: 10, color: color)
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 4, height: 2, color: color),
                const SizedBox(width: 2),
                Container(width: 4, height: 2, color: color),
                const SizedBox(width: 2),
                Container(width: 4, height: 2, color: color),
              ],
            ),
          const SizedBox(width: CMSpacing.sp1),
          Text(label,
              style: CMFonts.caption(size: 9.5, color: context.cmColors.noise)),
        ],
      );
    });
  }
}
