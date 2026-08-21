import 'package:cut_metrics/domain/activity_level.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Экран «Настройки» — макет `docs/screen-today-graph-summary-settings.html`.
///
/// Целевой темп (слайдер 0.3–1.4%, шаг 0.1) и уровень активности (1–5).
/// Без кнопки «Сохранить» — применение мгновенное (аннотация макета).
/// Блоки «Целевой вес», «Подписка», «Health-сервис» — вне скоупа Фазы 5.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Настройки', style: CMFonts.heading(size: 19)),
        backgroundColor: CMColors.surface0,
        foregroundColor: CMColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        children: [
          // ─── Целевой темп ────────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(CMSpacing.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Целевой темп изменения веса',
                      style: CMFonts.heading(size: 16)),
                  const SizedBox(height: CMSpacing.sp2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${RecommendationConfig.sliderMin.toStringAsFixed(1)}%',
                        style: CMFonts.caption(size: 11),
                      ),
                      Text(
                        '${vm.targetPace.toStringAsFixed(1)}%',
                        style: CMFonts.metric(size: 26, color: CMColors.signal),
                      ),
                      Text(
                        '${RecommendationConfig.sliderMax.toStringAsFixed(1)}%',
                        style: CMFonts.caption(size: 11),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: CMColors.signal,
                      inactiveTrackColor: CMColors.outline,
                      thumbColor: CMColors.signal,
                      overlayColor: CMColors.signalTint,
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
                    style: CMFonts.body(size: 13, color: CMColors.inkMuted),
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
                  Text('Уровень активности', style: CMFonts.heading(size: 16)),
                  const SizedBox(height: CMSpacing.sp2),
                  Text(
                    'Добавка расхода калорий на тренировки. Применяется сразу.',
                    style: CMFonts.body(size: 13, color: CMColors.inkMuted),
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
                            title: Text(level.title, style: CMFonts.label(size: 15)),
                            subtitle: Text(
                              level.description,
                              style: CMFonts.body(size: 13, color: CMColors.inkMuted),
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
        ],
      ),
    );
  }
}
