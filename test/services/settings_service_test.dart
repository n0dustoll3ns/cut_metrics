import 'package:cut_metrics/domain/activity_level.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
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
  });
}
