import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/ui/metric_card.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Экран "Сегодня" — карточки веса и шагов для текущей даты.
///
/// Контрол подтверждения встроен инлайн, без необходимости тапать по графику
/// (Фаза 3, секция 6 — "экран Сегодня" как самая частая точка входа).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final today = DateKey(DateTime.now());

    final d = today.value;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

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
            child: Text(dateStr, style: CMFonts.caption(size: 13)),
          ),

          // Карточка веса — инлайн, без тапа по графику
          MetricCard(
            key: ValueKey('today_weight'),
            date: today,
            type: MetricType.weight,
            viewModel: vm,
          ),
          const SizedBox(height: CMSpacing.sp4),

          // Карточка шагов — инлайн
          MetricCard(
            key: ValueKey('today_steps'),
            date: today,
            type: MetricType.steps,
            viewModel: vm,
          ),

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