import 'dart:async';

import 'package:cut_metrics/domain/activity_level.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/services/source_names.dart';
import 'package:cut_metrics/services/theme_controller.dart';
import 'package:cut_metrics/ui/debug_log_screen.dart';
import 'package:cut_metrics/ui/source_settings_screen.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Экран «Настройки» — макет `docs/screen-today-graph-summary-settings.html`.
///
/// Блоки: «Тема» (Фаза 6, D.3 — первый блок, сегмент Системная·Светлая·
/// Тёмная, дефолт системная), «Источники данных Health Connect» (Фаза 6, C.4 —
/// строки Вес/Шаги → подэкран выбора источника), целевой темп
/// (слайдер 0.3–1.4%, шаг 0.1) и уровень активности (1–5).
/// Без кнопки «Сохранить» — применение мгновенное (аннотация макета).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final colors = context.cmColors;

    return Scaffold(
      appBar: AppBar(title: Text('Настройки', style: CMFonts.heading(size: 19, color: colors.ink))),
      body: ListView(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        children: [
          // ─── Тема (Фаза 6, D.3) ──────────────────────────────────────────────
          const _ThemeBlock(),
          const SizedBox(height: CMSpacing.sp4),

          // ─── Источники данных Health Connect (Фаза 6, C.4) ──────────────────
          _SourcesBlock(colors: colors),
          const SizedBox(height: CMSpacing.sp4),

          // ─── Целевой темп ────────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(CMSpacing.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Целевой темп изменения веса',
                      style: CMFonts.heading(size: 16, color: colors.ink)),
                  const SizedBox(height: CMSpacing.sp2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${RecommendationConfig.sliderMin.toStringAsFixed(1)}%',
                        style: CMFonts.caption(size: 11, color: colors.noise),
                      ),
                      Text(
                        '${vm.targetPace.toStringAsFixed(1)}%',
                        style: CMFonts.metric(size: 26, color: colors.signal),
                      ),
                      Text(
                        '${RecommendationConfig.sliderMax.toStringAsFixed(1)}%',
                        style: CMFonts.caption(size: 11, color: colors.noise),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: colors.signal,
                      inactiveTrackColor: colors.outline,
                      thumbColor: colors.signal,
                      overlayColor: colors.signalTint,
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: vm.targetPace.clamp(
                        RecommendationConfig.sliderMin,
                        RecommendationConfig.sliderMax,
                      ),
                      min: RecommendationConfig.sliderMin,
                      max: RecommendationConfig.sliderMax,
                      // (1.4 − 0.3) / 0.1 = 11 делений.
                      divisions: ((RecommendationConfig.sliderMax -
                                  RecommendationConfig.sliderMin) /
                              RecommendationConfig.sliderStep)
                          .round(),
                      label: vm.targetPace.toStringAsFixed(1),
                      onChanged: (value) => vm.setTargetPace(value),
                    ),
                  ),
                  Text(
                    'Процент изменения веса в неделю. Применяется сразу.',
                    style: CMFonts.body(size: 13, color: colors.inkMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CMSpacing.sp4),

          // ─── Уровень активности ──────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(CMSpacing.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Уровень активности', style: CMFonts.heading(size: 16, color: colors.ink)),
                  const SizedBox(height: CMSpacing.sp2),
                  Text(
                    'Добавка расхода калорий на тренировки. Применяется сразу.',
                    style: CMFonts.body(size: 13, color: colors.inkMuted),
                  ),
                  const SizedBox(height: CMSpacing.sp2),
                  RadioGroup<ActivityLevel>(
                    groupValue: vm.activityLevel,
                    onChanged: (value) {
                      if (value != null) vm.setActivityLevel(value);
                    },
                    child: Column(
                      children: [
                        for (final level in ActivityLevel.values)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(level.title, style: CMFonts.label(size: 15, color: colors.ink)),
                            subtitle: Text(
                              level.description,
                              style: CMFonts.body(size: 13, color: colors.inkMuted),
                            ),
                            trailing: Radio<ActivityLevel>(value: level),
                            onTap: () => vm.setActivityLevel(level),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CMSpacing.sp8),
          const _VersionLabel(),
        ],
      ),
    );
  }
}

/// Блок «Тема» (Фаза 6, D.3): сегмент Системная · Светлая · Тёмная,
/// дефолт системный («Тёмная включается вместе с системной»).
class _ThemeBlock extends StatelessWidget {
  const _ThemeBlock();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final colors = context.cmColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Тема', style: CMFonts.heading(size: 16, color: colors.ink)),
            const SizedBox(height: CMSpacing.sp2),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Системная')),
                ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
              ],
              selected: {theme.mode},
              onSelectionChanged: (selection) => theme.setMode(selection.first),
            ),
            const SizedBox(height: CMSpacing.sp2),
            Text(
              'Тёмная включается вместе с системной',
              style: CMFonts.body(size: 12, color: colors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Блок «Источники данных Health Connect» (Фаза 6, C.4): строки «Вес» и
/// «Шаги», справа текущее значение («Авто» или имя приложения), шеврон.
/// Тап → [SourceSettingsScreen].
class _SourcesBlock extends StatelessWidget {
  final CMThemeColors colors;

  const _SourcesBlock({required this.colors});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();

    String currentLabel(MetricType metric) {
      final selection = vm.selectionFor(metric);
      return selection.isAuto
          ? 'Авто'
          : displaySourceName(selection.package ?? '');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Источники данных Health Connect',
                style: CMFonts.heading(size: 16, color: colors.ink)),
            const SizedBox(height: CMSpacing.sp2),
            for (final metric in MetricType.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  metric == MetricType.weight ? 'Вес' : 'Шаги',
                  style: CMFonts.label(size: 15, color: colors.ink),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentLabel(metric),
                      style: CMFonts.body(size: 13, color: colors.inkMuted),
                    ),
                    const SizedBox(width: CMSpacing.sp1),
                    Icon(Icons.chevron_right, size: 20, color: colors.noise),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SourceSettingsScreen(metric: metric),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Подпись версии внизу «Настроек» + скрытый вход в журнал отладки:
/// 5 тапов подряд (пауза между тапами не больше 3 с) открывают [DebugLogScreen].
///
/// Работает и в debug, и в release — обычному пользователю не мешает
/// (подпись версии и так стоит на экране). Без визуального отклика,
/// вход осознанно скрытый.
class _VersionLabel extends StatefulWidget {
  const _VersionLabel();

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  static const _tapsToOpen = 5;
  static const _tapResetAfter = Duration(seconds: 3);

  /// Синхронизировать вручную с `version` в `pubspec.yaml`.
  static const _version = '0.1.0';

  int _taps = 0;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _onTap() {
    _resetTimer?.cancel();
    _taps++;
    if (_taps >= _tapsToOpen) {
      _taps = 0;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DebugLogScreen()),
      );
      return;
    }
    _resetTimer = Timer(_tapResetAfter, () => _taps = 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque — тапы по пустому месту вокруг подписи тоже считаются.
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Center(
        child: Text(
          'Cut Metrics $_version',
          style: CMFonts.caption(size: 12, color: context.cmColors.noise),
        ),
      ),
    );
  }
}
