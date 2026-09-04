import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/ui/metric_card.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/today_screen.dart';
import 'package:cut_metrics/ui/weight_chart.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Экран «Тренд» — макет `docs/screen-today-graph-summary-settings.html`.
///
/// Сегменты Неделя / Месяц / 3 месяца («Весь срок» убран по решению
/// пользователя: полный диапазон — тяжёлый запрос и пересчёт EMA).
/// График веса+EMA с осью дат Фазы 6 (A3), тап по точке → карточка метрики
/// (U1). Ниже — среднесуточные показатели: Сон, Шаги, Активность (ккал).
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
                        ),
                      ),
                      Expanded(
                        child: _AvgMetric(
                          label: 'ШАГИ',
                          value: vm.avgSteps == null
                              ? '—'
                              : _formatThousands(vm.avgSteps!),
                          unit: '',
                        ),
                      ),
                      Expanded(
                        child: _AvgMetric(
                          label: 'АКТИВНОСТЬ',
                          value: vm.avgCaloriesPerDay == null
                              ? '—'
                              : '≈${vm.avgCaloriesPerDay!.round()}',
                          unit: 'ккал',
                        ),
                      ),
                    ],
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

  /// 8620 → «8 620» (разделитель разрядов, как в макете).
  String _formatThousands(int value) => value.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (match) => ' ',
      );
}

/// Ячейка среднесуточного показателя (значение Space Grotesk + mono-подпись).
class _AvgMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _AvgMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: CMFonts.caption(size: 10, color: colors.noise)),
        const SizedBox(height: CMSpacing.sp1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: CMFonts.metric(size: 20, color: colors.ink)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: CMSpacing.sp1),
              Text(unit, style: CMFonts.caption(size: 11, color: colors.noise)),
            ],
          ],
        ),
      ],
    );
  }
}

