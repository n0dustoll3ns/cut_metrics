import 'package:cut_metrics/domain/activity_level.dart';
import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = SettingsService();
  });

  group('дефолты', () {
    test('targetPace = 0.8', () async {
      expect(await service.loadTargetPace(),
          RecommendationConfig.defaultTargetPacePercent);
    });

    test('activityLevel = level1', () async {
      expect(await service.loadActivityLevel(), ActivityLevel.level1);
    });

    test('lastSummaryShownDate = null (ни разу не показывали)', () async {
      expect(await service.loadLastSummaryShownDate(), isNull);
    });

    test('Фаза 6: решения по источникам пусты', () async {
      expect(await service.loadSourceDecisions(MetricType.weight), isEmpty);
    });

    test('Фаза 6: выбор источника = Авто', () async {
      expect(
        await service.loadSourceSelection(MetricType.steps),
        const SourceSelection.auto(),
      );
    });

    test('Фаза 6: режим темы = system', () async {
      expect(await service.loadThemeModeName(), 'system');
    });
  });

  group('roundtrip save/load', () {
    test('targetPace', () async {
      await service.saveTargetPace(1.2);
      expect(await service.loadTargetPace(), 1.2);
    });

    test('activityLevel', () async {
      await service.saveActivityLevel(ActivityLevel.level4);
      expect(await service.loadActivityLevel(), ActivityLevel.level4);
    });

    test('lastSummaryShownDate', () async {
      final date = DateTime(2026, 8, 21, 10, 30);
      await service.saveLastSummaryShownDate(date);
      final loaded = await service.loadLastSummaryShownDate();
      expect(loaded, isNotNull);
      expect(loaded!.millisecondsSinceEpoch, date.millisecondsSinceEpoch);
    });

    test('Фаза 6: решение confirmed/refused по паре (метрика, источник)', () async {
      await service.saveSourceDecision(
        MetricType.weight, 'com.google.android.apps.fitness', ConfirmDecision.confirmed);
      await service.saveSourceDecision(
        MetricType.weight, 'com.watch.app', ConfirmDecision.refused);

      final decisions = await service.loadSourceDecisions(MetricType.weight);
      expect(decisions['com.google.android.apps.fitness'],
          ConfirmDecision.confirmed);
      expect(decisions['com.watch.app'], ConfirmDecision.refused);

      // Решения метрик не смешиваются.
      expect(await service.loadSourceDecisions(MetricType.steps), isEmpty);
    });

    test('Фаза 6: решение none удаляет ключ (сброс)', () async {
      await service.saveSourceDecision(
        MetricType.steps, 'com.watch.app', ConfirmDecision.refused);
      await service.saveSourceDecision(
        MetricType.steps, 'com.watch.app', ConfirmDecision.none);

      expect(await service.loadSourceDecisions(MetricType.steps), isEmpty);
    });

    test('Фаза 6: выбор источника app/auto roundtrip', () async {
      await service.saveSourceSelection(
        MetricType.weight, const SourceSelection.app('com.scale.app'));
      expect(
        await service.loadSourceSelection(MetricType.weight),
        const SourceSelection.app('com.scale.app'),
      );

      await service.saveSourceSelection(
        MetricType.weight, const SourceSelection.auto());
      expect(
        await service.loadSourceSelection(MetricType.weight),
        const SourceSelection.auto(),
      );
    });

    test('Фаза 6: режим темы roundtrip', () async {
      await service.saveThemeModeName('dark');
      expect(await service.loadThemeModeName(), 'dark');
      await service.saveThemeModeName('light');
      expect(await service.loadThemeModeName(), 'light');
      await service.saveThemeModeName('system');
      expect(await service.loadThemeModeName(), 'system');
    });
  });
}
