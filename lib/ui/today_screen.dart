import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/services/app_settings_opener.dart';
import 'package:cut_metrics/ui/metric_card.dart';
import 'package:cut_metrics/ui/months.dart';
import 'package:cut_metrics/ui/nutrition_card.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/weight_chart.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Экран «Сегодня» — макет `docs/screen-today-graph-summary-settings.html`.
///
/// Большое число — сглаженный вес (последняя точка EMA-линии), ниже — сырое
/// значение за сегодня, график веса за 30 дней (ось дат Фазы 6, A3),
/// карточки метрик Фазы 3 (U1: подтверждение остаётся здесь, инлайн;
/// состояния Фазы 6 — B.4), кнопка «Открыть саммари» (Фаза 7: после
/// карточек, как в макете), карточка «Питание» и подсказка профиля
/// (Фаза 7, B.2/B.5). Шаги и питание — «за вчера» (2026-09-16): день ещё
/// не завершён; вес — исключение (утренних данных достаточно).
class TodayScreen extends StatelessWidget {
  /// Переход на вкладку «Саммари» (с проверкой готовности — гейт в main).
  final VoidCallback onOpenSummary;

  /// Переход на вкладку «Настройки» (подсказка профиля, Фаза 7 B.5).
  final VoidCallback onOpenSettings;

  const TodayScreen({
    super.key,
    required this.onOpenSummary,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final colors = context.cmColors;
    final today = DateKey(DateTime.now());

    // Правило вывода «за вчера» (2026-09-16): шаги и питание показываем за
    // вчера — сбор данных за сегодня ещё не завершён. Вес — исключение
    // (утренних данных достаточно): большое число, «сырое значение сегодня»
    // и карточка веса остаются за сегодня.
    final yesterday = DateKey(DateTime.now().subtract(const Duration(days: 1)));

    final d = today.value;
    final dateStr = 'СЕГОДНЯ · ${d.day} ${kMonthsShort[d.month - 1].toUpperCase()}';

    final smoothed = vm.smoothedWeightToday;
    final rawToday = vm.getResolvedValue(today, MetricType.weight);

    return Scaffold(
      appBar: AppBar(
        title: Text('Сегодня', style: CMFonts.heading(size: 19, color: colors.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        children: [
          // Дата
          Padding(
            padding: const EdgeInsets.only(bottom: CMSpacing.sp4),
            child: Text(dateStr, style: CMFonts.caption(size: 12, color: colors.noise)),
          ),

          // Баннер «нет разрешений» — кнопка в системные настройки (2026-08-26).
          // Показывается вместо ErrorBox: отказ в разрешениях — не ошибка,
          // а состояние, требующее действия пользователя.
          if (vm.permissionsDenied) ...[
            const PermissionsBanner(),
            const SizedBox(height: CMSpacing.sp4),
          ],

          // Сглаженный вес — большое число
          Text(
            smoothed == null ? '—' : smoothed.toStringAsFixed(1),
            style: CMFonts.metric(size: 60, color: colors.ink),
          ),
          Text('кг · сглаженный вес', style: CMFonts.caption(size: 12, color: colors.noise)),
          const SizedBox(height: CMSpacing.sp2),

          // Сырое значение за сегодня
          Text(
            rawToday == null
                ? 'Сырое значение сегодня: —'
                : 'Сырое значение сегодня: ${rawToday.value.toStringAsFixed(1)} кг',
            style: CMFonts.body(size: 14, color: colors.inkMuted),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // График веса + EMA за 30 дней
          WeightChart(
            weightData: vm.weightData,
            emaData: vm.emaData,
            isLoading: vm.isLoading,
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

          // Карточка шагов — инлайн, за вчера (правило «за вчера», 2026-09-16)
          MetricCard(
            key: const ValueKey('today_steps'),
            date: yesterday,
            type: MetricType.steps,
            viewModel: vm,
          ),
          const SizedBox(height: CMSpacing.sp4),

          // Кнопка открытия саммари — после карточек, как в макете
          // (Фаза 7: порядок «карточки → кнопка → питание», решение 2026-09-14)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onOpenSummary,
              icon: const Icon(Icons.insights_outlined, size: 18),
              label: const Text('Открыть саммари'),
            ),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // Карточка «Питание» (Фаза 7, B.2) — за вчера: ручной «Итог дня» вводится за вчера и старше (2026-09-16)
          NutritionCard(
            key: const ValueKey('today_nutrition'),
            date: yesterday,
            viewModel: vm,
          ),

          // Подсказка профиля (Фаза 7, B.5): пока BMR не рассчитан ни одним
          // способом — ведёт в «Профиль расхода» на вкладке «Настройки».
          if (vm.needsProfileHint) ...[
            const SizedBox(height: CMSpacing.sp4),
            _ProfileHintCard(onTap: onOpenSettings),
          ],

          // Ошибка (если есть). Отказ в разрешениях покрыт баннером выше.
          if (vm.error != null && !vm.permissionsDenied) ...[
            const SizedBox(height: CMSpacing.sp4),
            ErrorBox(message: vm.error!),
          ],
        ],
      ),
    );
  }
}

/// Подсказка профиля (Фаза 7, B.5): «Рассчитаем ваш расход» — signal-tint
/// карточка под карточкой «Питание», пока BMR не рассчитан ни одним
/// способом (нет HC-BASAL и профиль неполон). Тап → вкладка «Настройки»
/// (блок «Профиль расхода»).
class _ProfileHintCard extends StatelessWidget {
  final VoidCallback onTap;

  const _ProfileHintCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CMRadius.md),
      child: Container(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        decoration: BoxDecoration(
          color: colors.signalTint,
          borderRadius: BorderRadius.circular(CMRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.local_fire_department_outlined,
                color: colors.signal, size: 20),
            const SizedBox(width: CMSpacing.sp2),
            Expanded(
              child: Text(
                'Рассчитаем ваш расход: укажите пол, год рождения и рост',
                style: CMFonts.body(size: 13, color: colors.ink),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colors.signal),
          ],
        ),
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
    final colors = context.cmColors;
    return Container(
      padding: const EdgeInsets.all(CMSpacing.sp4),
      decoration: BoxDecoration(
        color: colors.alertTint,
        borderRadius: BorderRadius.circular(CMRadius.md),
        border: Border.all(color: colors.alertBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.alert, size: 20),
          const SizedBox(width: CMSpacing.sp2),
          Expanded(
            child: Text(
              message,
              style: CMFonts.body(size: 14, color: colors.alert),
            ),
          ),
        ],
      ),
    );
  }
}

/// Баннер «разрешения Health Connect не выданы» (2026-08-26).
///
/// Показывается на «Сегодня» (вместо [ErrorBox]), когда
/// [DashboardViewModel.permissionsDenied]. Кнопка открывает страницу
/// приложения в системных настройках Android (Настройки → Приложения →
/// Cut Metrics → Разрешения) — согласовано с пользователем 2026-08-26.
///
/// После возврата в приложение `_AppShell` (WidgetsBindingObserver) тихо
/// перепроверяет права и перезагружает данные — баннер исчезает сам.
class PermissionsBanner extends StatelessWidget {
  const PermissionsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Container(
      padding: const EdgeInsets.all(CMSpacing.sp4),
      decoration: BoxDecoration(
        color: colors.alertTint,
        borderRadius: BorderRadius.circular(CMRadius.md),
        border: Border.all(color: colors.alertBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_outlined,
                color: colors.alert,
                size: 20,
              ),
              const SizedBox(width: CMSpacing.sp2),
              Expanded(
                child: Text(
                  'Нет разрешений для доступа к Health Connect. Откройте '
                  'настройки приложения и разрешите доступ к данным о здоровье.',
                  style: CMFonts.body(size: 14, color: colors.alert),
                ),
              ),
            ],
          ),
          const SizedBox(height: CMSpacing.sp3),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: AppSettingsOpener.openAppSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Открыть настройки разрешений'),
            ),
          ),
        ],
      ),
    );
  }
}
