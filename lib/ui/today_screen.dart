import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/ui/metric_card.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/weight_chart.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const kMonthsShort = [
  'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

/// Экран «Сегодня» — макет `docs/screen-today-graph-summary-settings.html`.
///
/// Большое число — сглаженный вес (последняя точка EMA-линии), ниже — сырое
/// значение за сегодня, график веса за 30 дней, кнопка «Открыть саммари» и
/// карточки метрик Фазы 3 (U1: подтверждение остаётся здесь, инлайн).
class TodayScreen extends StatelessWidget {
  /// Переход на вкладку «Саммари» (с проверкой готовности — гейт в main).
  final VoidCallback onOpenSummary;

  const TodayScreen({super.key, required this.onOpenSummary});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final today = DateKey(DateTime.now());

    final d = today.value;
    final dateStr = 'СЕГОДНЯ · ${d.day} ${kMonthsShort[d.month - 1].toUpperCase()}';

    final smoothed = vm.smoothedWeightToday;
    final rawToday = vm.getResolvedValue(today, MetricType.weight);

    return Scaffold(
      appBar: AppBar(
        title: Text('Сегодня', style: CMFonts.heading(size: 19)),
        backgroundColor: CMColors.surface0,
        foregroundColor: CMColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        children: [
          // Дата
          Padding(
            padding: const EdgeInsets.only(bottom: CMSpacing.sp4),
            child: Text(dateStr, style: CMFonts.caption(size: 12)),
          ),

          // Сглаженный вес — большое число
          Text(
            smoothed == null ? '—' : smoothed.toStringAsFixed(1),
            style: CMFonts.metric(size: 60, color: CMColors.ink),
          ),
          Text('кг · сглаженный вес', style: CMFonts.caption(size: 12)),
          const SizedBox(height: CMSpacing.sp2),

          // Сырое значение за сегодня
          Text(
            rawToday == null
                ? 'Сырое значение сегодня: —'
                : 'Сырое значение сегодня: ${rawToday.value.toStringAsFixed(1)} кг',
            style: CMFonts.body(size: 14, color: CMColors.inkMuted),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // График веса + EMA за 30 дней
          WeightChart(
            weightData: vm.weightData,
            emaData: vm.emaData,
            isLoading: vm.isLoading,
          ),
          const SizedBox(height: CMSpacing.sp4),

          // Кнопка открытия саммари
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onOpenSummary,
              icon: const Icon(Icons.insights_outlined, size: 18),
              label: const Text('Открыть саммари'),
            ),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // Карточка веса — инлайн, без тапа по графику
          MetricCard(
            key: const ValueKey('today_weight'),
            date: today,
            type: MetricType.weight,
            viewModel: vm,
          ),
          const SizedBox(height: CMSpacing.sp4),

          // Карточка шагов — инлайн
          MetricCard(
            key: const ValueKey('today_steps'),
            date: today,
            type: MetricType.steps,
            viewModel: vm,
          ),

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

/// Блок ошибки (alert-токены дизайн-системы). Общий для экранов Фазы 5.
class ErrorBox extends StatelessWidget {
  final String message;

  const ErrorBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              message,
              style: CMFonts.body(size: 14, color: CMColors.alert),
            ),
          ),
        ],
      ),
    );
  }
}
