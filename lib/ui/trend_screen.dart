import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/ui/energy_balance_chart.dart';
import 'package:cut_metrics/ui/calc_detail_sheet.dart';
import 'package:cut_metrics/ui/format.dart';
import 'package:cut_metrics/ui/metric_card.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/today_screen.dart';
import 'package:cut_metrics/ui/weight_chart.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Экран «Тренд» — макет `docs/screen-today-graph-summary-settings.html`.
///
/// Сегменты Неделя / Месяц / 3 месяца. График веса+EMA с осью дат Фазы 6
/// (A3), под ним график энергобаланса (Фаза 7, B.3 — реагирует на сегмент),
/// тап по точке → карточка метрики (U1). Среднесуточные: Сон / Шаги /
/// Расход и второй строкой Приход + Б/Ж/У с покрытием (Фаза 7).
class TrendScreen extends StatefulWidget {
  const TrendScreen({super.key});

  @override
  State<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends State<TrendScreen> {
  static const _segments = {
    7: 'Неделя',
    30: 'Месяц',
    RecommendationConfig.maxTrendDays: '3 месяца',
  };

  /// Дата, выбранная тапом по графику (для карточки, Фаза 3 → U1).
  DateKey? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final colors = context.cmColors;

    return Scaffold(
      appBar: AppBar(
        title: Text('Тренд', style: CMFonts.heading(size: 19, color: colors.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        children: [
          SegmentedButton<int>(
            segments: [
              for (final entry in _segments.entries)
                ButtonSegment(value: entry.key, label: Text(entry.value)),
            ],
            selected: {vm.rangeDays},
            onSelectionChanged: (selection) => vm.setRange(selection.first),
          ),
          const SizedBox(height: CMSpacing.sp4),

          WeightChart(
            weightData: vm.weightData,
            emaData: vm.emaData,
            isLoading: vm.isLoading,
            onTapPoint: (weightDay) =>
                setState(() => _selectedDate = weightDay.date),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // График энергобаланса (Фаза 7, B.3): под графиком веса,
          // реагирует на сегмент периода.
          EnergyBalanceChart(
            balanceData: vm.balanceData,
            targetDeficitKcalPerDay: vm.targetDeficitKcalPerDay,
            daysWithoutNutrition: vm.daysWithoutNutritionInRange,
            isLoading: vm.isLoading,
            // CalcDetail (§6): «Как рассчитано» в тултипе столбца.
            onCalcDetail: (date) =>
                showCalcDetailSheet(context, vm.balanceTraceFor(date)),
          ),
          const SizedBox(height: CMSpacing.sp4),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(CMSpacing.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Среднесуточные показатели',
                      style: CMFonts.heading(size: 16, color: colors.ink)),
                  const SizedBox(height: CMSpacing.sp3),
                  Row(
                    children: [
                      Expanded(
                        child: _AvgMetric(
                          label: 'СОН',
                          value: vm.avgSleepHours == null
                              ? '—'
                              : vm.avgSleepHours!.toStringAsFixed(1),
                          unit: 'ч',
                          onCalcDetail: vm.avgSleepHours == null
                              ? null
                              : () => showCalcDetailSheet(
                                  context, vm.avgSleepTrace()),
                        ),
                      ),
                      Expanded(
                        child: _AvgMetric(
                          label: 'ШАГИ',
                          value: vm.avgSteps == null
                              ? '—'
                              : formatThousands(vm.avgSteps!),
                          unit: '',
                          onCalcDetail: vm.avgSteps == null
                              ? null
                              : () => showCalcDetailSheet(
                                  context, vm.avgStepsTrace()),
                        ),
                      ),
                      Expanded(
                        child: _AvgMetric(
                          label: 'РАСХОД',
                          value: vm.avgExpenditure == null
                              ? '—'
                              : '≈${formatThousands(vm.avgExpenditure!)}',
                          unit: 'ккал',
                          coverage: vm.expenditureDaysInRange > 0
                              ? 'по ${vm.expenditureDaysInRange} дн.'
                              : null,
                          onCalcDetail: vm.avgExpenditure == null
                              ? null
                              : () => showCalcDetailSheet(
                                  context, vm.avgExpenditureTrace()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CMSpacing.sp3),
                  Divider(color: colors.outline, height: 1),
                  const SizedBox(height: CMSpacing.sp3),
                  Row(
                    children: [
                      Expanded(
                        child: _AvgMetric(
                          label: 'ПРИХОД',
                          value: vm.avgCaloriesIn == null
                              ? '—'
                              : formatThousands(vm.avgCaloriesIn!),
                          unit: 'ккал',
                          coverage: vm.intakeDaysInRange > 0
                              ? 'по ${vm.intakeDaysInRange} дн.'
                              : null,
                          onCalcDetail: vm.avgCaloriesIn == null
                              ? null
                              : () => showCalcDetailSheet(
                                  context, vm.avgIntakeTrace()),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _AvgMetric(
                          label: 'Б / Ж / У',
                          value: vm.avgMacros == null
                              ? '—'
                              : '${vm.avgMacros!.protein!.round()} / '
                                  '${vm.avgMacros!.fat!.round()} / '
                                  '${vm.avgMacros!.carbs!.round()}',
                          unit: 'г',
                          coverage: vm.intakeDaysInRange > 0
                              ? 'по ${vm.intakeDaysInRange} дн.'
                              : null,
                          onCalcDetail: vm.avgMacros == null
                              ? null
                              : () => showCalcDetailSheet(
                                  context, vm.avgMacrosTrace()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CMSpacing.sp2),
                  Text(
                    'Сегодня не учитывается — день ещё не завершён',
                    style: CMFonts.caption(size: 10, color: colors.noise),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // Карточка метрики для выбранной даты (тап по графику, U1)
          if (_selectedDate != null) ...[
            MetricCard(
              key: ValueKey('trend_$_selectedDate'),
              date: _selectedDate!,
              type: MetricType.weight,
              viewModel: vm,
            ),
            const SizedBox(height: CMSpacing.sp2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _selectedDate = null),
                child: const Text('Закрыть карточку'),
              ),
            ),
          ],

          // Ошибка (если есть)
          if (vm.error != null) ...[
            const SizedBox(height: CMSpacing.sp4),
            ErrorBox(message: vm.error!),
          ],
        ],
      ),
    );
  }

}

/// Ячейка среднесуточного показателя (значение Space Grotesk + mono-подпись).
/// [coverage] — строка покрытия «по N дн.» под значением (Фаза 7, mono 9.5).
class _AvgMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final String? coverage;

  /// CalcDetail (§6): тап по ячейке → трасса среднесуточного.
  /// `null` — ячейка не тапабельна (данных нет).
  final VoidCallback? onCalcDetail;

  const _AvgMetric({
    required this.label,
    required this.value,
    required this.unit,
    this.coverage,
    this.onCalcDetail,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    final cell = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: CMFonts.caption(size: 10, color: colors.noise)),
            if (onCalcDetail != null) ...[
              const SizedBox(width: 2),
              CalcInfoIcon(tooltip: 'Как рассчитано', onTap: onCalcDetail!),
            ],
          ],
        ),
        const SizedBox(height: CMSpacing.sp1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                style: CMFonts.metric(size: 20, color: colors.ink),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: CMSpacing.sp1),
              Text(unit, style: CMFonts.caption(size: 11, color: colors.noise)),
            ],
          ],
        ),
        if (coverage != null) ...[
          const SizedBox(height: 2),
          Text(
            coverage!,
            style: CMFonts.caption(size: 9.5, color: colors.noise),
          ),
        ],
      ],
    );
    // Тапабельность всей ячейки + иконка ⓘ (CalcDetail, §6).
    return onCalcDetail == null
        ? cell
        : InkWell(
            onTap: onCalcDetail,
            borderRadius: BorderRadius.circular(CMRadius.sm),
            child: cell,
          );
  }
}

