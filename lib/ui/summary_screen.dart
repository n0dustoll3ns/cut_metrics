import 'package:cut_metrics/domain/recommendation_engine.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/today_screen.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Экран «Саммари» — макет `docs/screen-today-graph-summary-settings.html`.
///
/// Гейт доступа — в main (`_AppShellState._selectTab`): вкладка открывается
/// только если `computeWeeklySummary()` != null, иначе снекбар
/// [RecommendationConfig.summaryNotReadyMessage]. Пересчёт — при каждом
/// открытии (U3), `lastSummaryShownDate` пишется в момент переключения вкладки.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final summary = vm.computeWeeklySummary();

    return Scaffold(
      appBar: AppBar(
        title: Text('Саммари', style: CMFonts.heading(size: 19)),
        backgroundColor: CMColors.surface0,
        foregroundColor: CMColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        children: [
          if (summary == null)
            _NotReady()
          else
            _SummaryBody(summary: summary),
          if (vm.error != null) ...[
            const SizedBox(height: CMSpacing.sp4),
            ErrorBox(message: vm.error!),
          ],
        ],
      ),
    );
  }
}

/// Плейсхолдер: гейт в main не пропустил бы, но данные могли измениться.
class _NotReady extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CMSpacing.sp12),
        child: Text(
          RecommendationConfig.summaryNotReadyMessage,
          style: CMFonts.body(size: 14, color: CMColors.noise),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Тело саммари по макету.
class _SummaryBody extends StatelessWidget {
  final WeeklySummary summary;

  const _SummaryBody({required this.summary});

  String get _dateRange {
    final s = summary.rangeStart;
    final e = summary.rangeEnd;
    final sStr = '${s.day} ${kMonthsShort[s.month - 1].toUpperCase()}';
    final eStr = '${e.day} ${kMonthsShort[e.month - 1].toUpperCase()}';
    return '$sStr — $eStr';
  }

  String get _statusTitle => switch (summary.status) {
        PaceStatus.inPace => 'В темпе',
        PaceStatus.tooSlow => 'Слишком медленно',
        PaceStatus.tooFast => 'Слишком быстро',
      };

  Color get _statusColor => switch (summary.status) {
        PaceStatus.inPace => CMColors.steady,
        PaceStatus.tooSlow => CMColors.alert,
        PaceStatus.tooFast => CMColors.alert,
      };

  /// Знак темпа: снижение — «−», рост — «+».
  String get _paceValue {
    final v = summary.actualPacePercent;
    final sign = v < 0 ? '−' : '+';
    return '$sign${v.abs().toStringAsFixed(1)}%';
  }

  /// «−0.5 кг за неделю» / «+0.3 кг за неделю».
  String get _kgChange {
    final v = summary.weightChangeKg;
    final sign = v < 0 ? '−' : '+';
    return '$sign${v.abs().toStringAsFixed(1)} кг за неделю';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Диапазон окна
            Text(_dateRange, style: CMFonts.caption(size: 12)),
            const SizedBox(height: CMSpacing.sp4),

            // Статус: точка-индикатор + заголовок
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: CMSpacing.sp2),
                Text(_statusTitle, style: CMFonts.heading(size: 20)),
              ],
            ),
            const SizedBox(height: CMSpacing.sp4),

            // Темп %/нед + изменение в кг
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _paceValue,
                  style: CMFonts.metric(size: 44, color: CMColors.signal),
                ),
                const SizedBox(width: CMSpacing.sp3),
                Expanded(
                  child: Text(
                    _kgChange,
                    style: CMFonts.body(size: 14, color: CMColors.inkMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CMSpacing.sp3),

            // Вывод
            Text(
              summary.conclusionText,
              style: CMFonts.body(size: 14, color: CMColors.inkMuted),
            ),
            const SizedBox(height: CMSpacing.sp4),
            const Divider(color: CMColors.outline, height: 1),
            const SizedBox(height: CMSpacing.sp4),

            // Рекомендация
            Text(
              RecommendationConfig.summaryRecLabel.toUpperCase(),
              style: CMFonts.caption(size: 11),
            ),
            const SizedBox(height: CMSpacing.sp2),
            Text(
              summary.recommendationText,
              style: CMFonts.body(size: 15, color: CMColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}
