import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/services/source_names.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Подэкран «Источник: Вес / Шаги» — Фаза 6, C.4 (макет в
/// `docs/screen-today-graph-summary-settings.html`).
///
/// Радио-список: «Авто — приложение выбирает источник само» + найденные
/// приложения (имя из словаря `source_names.dart`, пакет мелко, статус
/// решения: Доверяем / Отклонён / Спрашивает).
///
/// - Отклонённый источник выбрать нельзя — сначала «Сбросить решение»
///   (действие «⋯» в строке).
/// - Выбор источника = доверие: карточка метрики больше не спрашивает
///   «Ок / Не ок» (тихая, autoConfirmed).
/// - Список строится по сырым точкам сессии — без запросов к Health Connect.
///
/// Вход: блок «Источники данных Health Connect» в «Настройках» и меню «⋯»
/// карточки метрики.
class SourceSettingsScreen extends StatelessWidget {
  final MetricType metric;

  const SourceSettingsScreen({super.key, required this.metric});

  String get _title => metric == MetricType.weight ? 'Источник: Вес' : 'Источник: Шаги';

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final colors = context.cmColors;
    final selection = vm.selectionFor(metric);
    final sources = vm.availableSources(metric);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Авто'),
                  subtitle: Text(
                    'Приложение выбирает источник само',
                    style: CMFonts.body(size: 13, color: colors.inkMuted),
                  ),
                  trailing: _RadioDot(selected: selection.isAuto),
                  onTap: () => vm.setSourceSelection(
                    metric,
                    const SourceSelection.auto(),
                  ),
                ),
                for (final package in sources)
                  _SourceRow(
                    metric: metric,
                    package: package,
                    selected: selection.package == package,
                  ),
                if (sources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(CMSpacing.sp4),
                    child: Text(
                      'Источники не найдены — загрузите данные на вкладке «Сегодня»',
                      style: CMFonts.body(size: 13, color: colors.noise),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CMSpacing.sp4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CMSpacing.sp4),
            child: Text(
              'Один источник на метрику. Выбор источника = доверие: '
              'карточка метрики не спрашивает «Ок / Не ок». Отклонённый '
              'источник сначала «Сбросить решение» (⋯ в строке).',
              style: CMFonts.body(size: 12, color: colors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка одного приложения-источника: имя, пакет, статус решения,
/// радио выбора и меню «⋯» («Сбросить решение»).
class _SourceRow extends StatelessWidget {
  final MetricType metric;
  final String package;
  final bool selected;

  const _SourceRow({
    required this.metric,
    required this.package,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final colors = context.cmColors;
    final decision = vm.decisionFor(metric, package);
    final refused = decision == ConfirmDecision.refused;

    final (statusText, statusColor) = switch (decision) {
      ConfirmDecision.confirmed => ('Доверяем', colors.steady),
      ConfirmDecision.refused => ('Отклонён', colors.alert),
      ConfirmDecision.none => ('Спрашивает', colors.inkMuted),
    };

    return ListTile(
      enabled: !refused,
      title: Text(
        displaySourceName(package),
        style: CMFonts.label(size: 15, color: refused ? colors.inkMuted : colors.ink),
      ),
      subtitle: Text(
        package,
        style: CMFonts.caption(size: 10, color: colors.noise),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(statusText, style: CMFonts.caption(size: 10, color: statusColor)),
          const SizedBox(width: CMSpacing.sp2),
          // «⋯»: сбросить решение (для отклонённых — единственный путь
          // снова сделать источник выбираемым).
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'Действия',
            onSelected: (action) {
              if (action == 'reset') vm.resetDecision(metric, package);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset',
                child: Text('Сбросить решение'),
              ),
            ],
          ),
          _RadioDot(selected: selected, enabled: !refused),
        ],
      ),
      onTap: refused
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Источник «${displaySourceName(package)}» отклонён — '
                    'сначала сбросьте решение (⋯)',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          : () => vm.setSourceSelection(metric, SourceSelection.app(package)),
    );
  }
}

/// Индикатор радио-выбора (круг с точкой) — собственный вместо
/// deprecated `Radio.groupValue/onChanged`. Отключённое состояние —
/// полупрозрачность (отклонённый источник выбрать нельзя).
class _RadioDot extends StatelessWidget {
  final bool selected;
  final bool enabled;

  const _RadioDot({required this.selected, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colors.signal : colors.outlineStrong,
            width: 2,
          ),
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors.signal,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
