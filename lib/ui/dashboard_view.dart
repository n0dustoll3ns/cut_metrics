import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/ui/metric_card.dart';
import 'package:cut_metrics/ui/steps_chart.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/weight_chart.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Экран дашборда — графики веса/EMA и шагов.
///
/// Тап по точке графика открывает карточку метрики для тапнутой даты
/// (Фаза 3, секция 6).
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  /// Дата и метрика, выбранная тапом по графику (для показа карточки).
  DateKey? _selectedDate;
  MetricType? _selectedMetric;

  void _selectDate(DateKey date, MetricType metric) {
    setState(() {
      _selectedDate = date;
      _selectedMetric = metric;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Дашборд', style: CMFonts.heading(size: 19)),
        backgroundColor: CMColors.surface0,
        foregroundColor: CMColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        children: [
          // График веса
          WeightChart(
            weightData: vm.weightData,
            emaData: vm.emaData,
            isLoading: vm.isLoading,
            onTapPoint: (weightDay) => _selectDate(weightDay.date, MetricType.weight),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // График шагов
          StepsChart(
            stepsData: vm.stepsData,
            isLoading: vm.isLoading,
            onTapBar: (stepsDay) => _selectDate(stepsDay.date, MetricType.steps),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // Карточка метрики для выбранной даты (если есть)
          if (_selectedDate != null && _selectedMetric != null) ...[
            MetricCard(
              key: ValueKey('${_selectedDate!}_${_selectedMetric!}'),
              date: _selectedDate!,
              type: _selectedMetric!,
              viewModel: vm,
            ),
            const SizedBox(height: CMSpacing.sp2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  _selectedDate = null;
                  _selectedMetric = null;
                }),
                child: const Text('Закрыть карточку'),
              ),
            ),
          ],

          // Ошибка (если есть)
          if (vm.error != null) ...[
            const SizedBox(height: CMSpacing.sp4),
            Container(
              padding: const EdgeInsets.all(CMSpacing.sp4),
              decoration: BoxDecoration(
                color: CMColors.alertTint,
                borderRadius: BorderRadius.circular(CMRadius.md),
                border: Border.all(color: CMColors.alertBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: CMColors.alert, size: 20),
                  const SizedBox(width: CMSpacing.sp2),
                  Expanded(
                    child: Text(
                      vm.error!,
                      style: CMFonts.body(size: 14, color: CMColors.alert),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}