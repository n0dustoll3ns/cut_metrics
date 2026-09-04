import 'package:cut_metrics/domain/activity_level.dart';
import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/recommendation_engine.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/repo/mock_health_repository.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHealthRepository repo;
  late HealthDataProcessor processor;
  late DashboardViewModel vm;

  Future<void> setupViewModel({List<double> externalWeights = const []}) async {
    repo = MockHealthRepository();
    processor = HealthDataProcessor(appPackageId: kAppPackageId);

    final now = DateTime.now();
    for (var i = 0; i < externalWeights.length; i++) {
      final date = now.subtract(Duration(days: externalWeights.length - 1 - i));
      repo.addExternalWeight(date, externalWeights[i]);
    }

    vm = DashboardViewModel(
      repository: repo,
      processor: processor,
      autoLoad: false,
    );
    await vm.load();
  }

  group('getResolvedValue', () {
    test('returns null when no data (missing state)', () async {
      await setupViewModel();
      final today = DateKey(DateTime.now());
      expect(vm.getResolvedValue(today, MetricType.weight), isNull);
    });

    test('returns external source for external record', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      final today = DateKey(DateTime.now());
      final value = vm.getResolvedValue(today, MetricType.weight);
      expect(value, isNotNull);
      expect(value!.source, DataSource.external);
      expect(value.value, 78.0);
    });
  });

  group('submitManualValue', () {
    test('writes manual record and updates cache to manual', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      final today = DateKey(DateTime.now());
      await vm.submitManualValue(today, MetricType.weight, 77.5);

      final value = vm.getResolvedValue(today, MetricType.weight);
      expect(value, isNotNull);
      expect(value!.source, DataSource.manual);
      expect(value.value, 77.5);
      expect(await repo.hasManualRecord(today, MetricType.weight), isTrue);
    });

    test('manual overrides external (Tier 1 > Tier 2)', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      final today = DateKey(DateTime.now());
      expect(vm.getResolvedValue(today, MetricType.weight)!.source,
          DataSource.external);
      await vm.submitManualValue(today, MetricType.weight, 77.0);
      final value = vm.getResolvedValue(today, MetricType.weight);
      expect(value!.source, DataSource.manual);
      expect(value.value, 77.0);
    });
  });

  group('cancelManualValue', () {
    test('rolls back to external after canceling manual', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      final today = DateKey(DateTime.now());
      await vm.submitManualValue(today, MetricType.weight, 77.0);
      expect(vm.getResolvedValue(today, MetricType.weight)!.source,
          DataSource.manual);
      await vm.cancelManualValue(today, MetricType.weight);
      final value = vm.getResolvedValue(today, MetricType.weight);
      expect(value!.source, DataSource.external);
      expect(value.value, 78.0);
    });

    test('rolls back to missing if no external data', () async {
      await setupViewModel();
      final today = DateKey(DateTime.now());
      await vm.submitManualValue(today, MetricType.weight, 77.0);
      expect(vm.getResolvedValue(today, MetricType.weight)!.source,
          DataSource.manual);
      await vm.cancelManualValue(today, MetricType.weight);
      expect(vm.getResolvedValue(today, MetricType.weight), isNull);
    });
  });

  group('EMA recalculation', () {
    test('editing historical weight changes EMA for subsequent dates', () async {
      await setupViewModel(externalWeights: [80, 79, 78, 77, 76]);
      final emaBefore = List.of(vm.emaData);

      final earliestDate =
          DateKey(DateTime.now().subtract(const Duration(days: 4)));
      await vm.submitManualValue(earliestDate, MetricType.weight, 90.0);

      final emaAfter = vm.emaData;
      expect(emaAfter.length, equals(emaBefore.length));
      expect(emaAfter, isNot(equals(emaBefore)));
    });

    test('editing steps does not trigger EMA recalculation', () async {
      await setupViewModel(externalWeights: [80, 79, 78, 77, 76]);

      final now = DateTime.now();
      for (var i = 0; i < 5; i++) {
        final date = now.subtract(Duration(days: 4 - i));
        repo.addExternalSteps(date, 1000 * (i + 1));
      }

      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();

      final emaBefore = List.of(vm.emaData);
      final historicalDate = DateKey(now.subtract(const Duration(days: 4)));
      await vm.submitManualValue(historicalDate, MetricType.steps, 50000);

      final emaAfter = vm.emaData;
      expect(emaAfter.length, equals(emaBefore.length));
      for (var i = 0; i < emaAfter.length; i++) {
        expect(emaAfter[i].weight, closeTo(emaBefore[i].weight, 0.001));
      }
    });
  });

  group('"Ок" пишет решение, а не данные (Фаза 6, B.2)', () {
    test('confirmSource: решение confirmed, записи данных нет, карточка тихая', () async {
      await setupViewModel(externalWeights: [80]);
      final today = DateKey(DateTime.now());
      final value = vm.getResolvedValue(today, MetricType.weight);
      final package = value!.sourcePackage!;
      final pointsBefore = repo.points.length;

      await vm.confirmSource(MetricType.weight, package);

      // Пишет решение — данные не пишет (Фаза 6, B.2).
      expect(vm.decisionFor(MetricType.weight, package), ConfirmDecision.confirmed);
      expect(repo.points.length, pointsBefore);
      expect(vm.isSourceTrusted(MetricType.weight, package), isTrue);

      // Значение не изменилось (тот же источник и величина).
      final after = vm.getResolvedValue(today, MetricType.weight);
      expect(after!.value, 80.0);
    });

    test('confirmSource: новый источник без решения снова «спрашивает»', () async {
      await setupViewModel(externalWeights: [80]);
      final package =
          vm.getResolvedValue(DateKey(DateTime.now()), MetricType.weight)!.sourcePackage!;
      await vm.confirmSource(MetricType.weight, package);
      expect(vm.isSourceTrusted(MetricType.weight, package), isTrue);
      // Другой источник не доверен:
      expect(vm.isSourceTrusted(MetricType.weight, 'com.unknown.app'), isFalse);
    });
  });

  group('Шаги из сырых точек, батчевость (Фаза 6, A2 / Фаза 4 DoD 3)', () {
    test('load() резолвит шаги по сырым точкам без aggregate-вызовов', () async {
      await setupViewModel(externalWeights: [80, 79, 78, 77, 76]);

      final now = DateTime.now();
      for (var i = 0; i < 5; i++) {
        final date = now.subtract(Duration(days: 4 - i));
        repo.addExternalSteps(date, 1000 * (i + 1));
      }

      repo.fetchRawDataCallCount = 0;
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();

      // Вес + шаги + сон = 3 батчевых чтения, aggregate-API удалены.
      expect(repo.fetchRawDataCallCount, 3);

      // Шаги за сегодня = 5000 (последний день) из сырых точек.
      expect(vm.getResolvedValue(DateKey(now), MetricType.steps)!.value, 5000);
    });

    test('load() makes exactly 3 fetchRawData calls (weight + steps + sleep)', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);

      repo.fetchRawDataCallCount = 0;
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();

      // Один вызов для WEIGHT + один для STEPS + один для SLEEP = 3 (Фаза 5).
      expect(repo.fetchRawDataCallCount, 3);
    });
  });

  group('Фаза 6, B/C: отказ, выбор источника, перерезолюция', () {
    test('refuseSource: данные источника исчезают, isSourceRefused = true', () async {
      await setupViewModel(externalWeights: [80]);
      final today = DateKey(DateTime.now());
      final package =
          vm.getResolvedValue(today, MetricType.weight)!.sourcePackage!;

      await vm.refuseSource(MetricType.weight, package);

      expect(vm.decisionFor(MetricType.weight, package), ConfirmDecision.refused);
      expect(vm.getResolvedValue(today, MetricType.weight), isNull);
      expect(vm.isSourceRefused(today, MetricType.weight), isTrue);
    });

    test('refuseSource не трогает другие источники', () async {
      final repo2 = MockHealthRepository();
      final processor2 = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo2.addExternalWeight(now, 70.0, sourcePackage: 'com.bad.app');
      repo2.addExternalWeight(now, 71.0, sourcePackage: 'com.good.app');
      final vm2 = DashboardViewModel(
        repository: repo2,
        processor: processor2,
        autoLoad: false,
      );
      await vm2.load();

      await vm2.refuseSource(MetricType.weight, 'com.bad.app');

      final value = vm2.getResolvedValue(DateKey(now), MetricType.weight);
      expect(value, isNotNull);
      expect(value!.sourcePackage, 'com.good.app');
      expect(value.value, 71.0);
    });

    test('setSourceSelection перерезолвляет без обращений к репозиторию', () async {
      final repo2 = MockHealthRepository();
      final processor2 = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo2.addExternalWeight(now, 70.0, sourcePackage: 'com.scale.app');
      repo2.addExternalWeight(now, 71.0, sourcePackage: 'com.watch.app');
      final vm2 = DashboardViewModel(
        repository: repo2,
        processor: processor2,
        autoLoad: false,
      );
      await vm2.load();
      expect(repo2.fetchRawDataCallCount, 3);

      // Выбор источника — только из памяти, без новых запросов.
      final callsBefore = repo2.fetchRawDataCallCount;
      await vm2.setSourceSelection(
        MetricType.weight,
        const SourceSelection.app('com.scale.app'),
      );

      expect(repo2.fetchRawDataCallCount, callsBefore);
      expect(vm2.selectionFor(MetricType.weight).package, 'com.scale.app');
      final value = vm2.getResolvedValue(DateKey(now), MetricType.weight);
      expect(value!.sourcePackage, 'com.scale.app');
      expect(value.value, 70.0);
      // Выбор = доверие: карточка тихая (C.4).
      expect(vm2.isSourceTrusted(MetricType.weight, 'com.scale.app'), isTrue);
    });

    test('resetDecision возвращает «спрашивать» и данные источника', () async {
      await setupViewModel(externalWeights: [80]);
      final today = DateKey(DateTime.now());
      final package =
          vm.getResolvedValue(today, MetricType.weight)!.sourcePackage!;

      await vm.refuseSource(MetricType.weight, package);
      expect(vm.getResolvedValue(today, MetricType.weight), isNull);

      await vm.resetDecision(MetricType.weight, package);
      expect(vm.decisionFor(MetricType.weight, package), ConfirmDecision.none);
      expect(vm.getResolvedValue(today, MetricType.weight), isNotNull);
      expect(vm.isSourceTrusted(MetricType.weight, package), isFalse);
    });

    test('availableSources: список из сырых точек сессии, без нашего пакета', () async {
      final repo2 = MockHealthRepository();
      final processor2 = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo2.addExternalWeight(now, 70.0, sourcePackage: 'com.scale.app');
      repo2.addExternalWeight(now, 70.5, sourcePackage: 'com.watch.app');
      repo2.addManualWeight(now.subtract(const Duration(days: 1)), 72.0);
      final vm2 = DashboardViewModel(
        repository: repo2,
        processor: processor2,
        autoLoad: false,
      );
      await vm2.load();

      expect(
        vm2.availableSources(MetricType.weight),
        ['com.scale.app', 'com.watch.app'],
      );
    });

    test('submitManualValue возвращает true при успехе', () async {
      await setupViewModel(externalWeights: [80]);
      final today = DateKey(DateTime.now());
      final ok = await vm.submitManualValue(today, MetricType.weight, 77.0);
      expect(ok, isTrue);
      expect(
        vm.getResolvedValue(today, MetricType.weight)!.source,
        DataSource.manual,
      );
    });
  });

  group('Phase 5: range / averages / summary', () {
    test('setRange changes visible range without new fetches', () async {
      await setupViewModel(externalWeights: [80, 79, 78, 77, 76]);

      repo.fetchRawDataCallCount = 0;
      vm.setRange(7);
      expect(repo.fetchRawDataCallCount, 0);
      expect(vm.rangeDays, 7);
      expect(vm.start.isAfter(DateTime.now().subtract(const Duration(days: 7))), isTrue);
    });

    test('computeWeeklySummary returns null with too few points', () async {
      await setupViewModel(externalWeights: [80]); // 1 точка в окне
      expect(vm.computeWeeklySummary(), isNull);
    });

    test('computeWeeklySummary computes with enough recent points', () async {
      await setupViewModel(externalWeights: [100, 99.8, 99.6, 99.4, 99.2]);
      final summary = vm.computeWeeklySummary();
      expect(summary, isNotNull);
      expect(summary!.status, anyOf(PaceStatus.inPace, PaceStatus.tooSlow, PaceStatus.tooFast));
      // Темп снижения: вес падает → фактический темп отрицательный.
      expect(summary.actualPacePercent, lessThan(0));
      expect(summary.recommendationText, isNotEmpty);
    });

    test('avgSleepHours counts only nights with data', () async {
      await setupViewModel(externalWeights: [80]);

      final now = DateTime.now();
      // Ночь: вчера 23:00 → сегодня 07:00 = 8 ч (день сна — сегодня).
      repo.addSleepAsleep(
        DateTime(now.year, now.month, now.day - 1, 23),
        DateTime(now.year, now.month, now.day, 7),
      );
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();

      expect(vm.avgSleepHours, closeTo(8, 1e-9));
    });

    test('avgSteps counts days with records', () async {
      await setupViewModel(externalWeights: [80]);

      final now = DateTime.now();
      repo.addExternalSteps(now, 10000);
      repo.addExternalSteps(now.subtract(const Duration(days: 1)), 6000);
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();

      expect(vm.avgSteps, 8000);
    });

    test('avgCaloriesPerDay is null without any weight', () async {
      await setupViewModel();
      expect(vm.avgCaloriesPerDay, isNull);
    });

    test('avgCaloriesPerDay = steps kcal + level additive', () async {
      await setupViewModel(externalWeights: [80]); // вес 80 кг
      await vm.setActivityLevel(ActivityLevel.level1);

      final now = DateTime.now();
      repo.addExternalSteps(now, 10000); // 400 ккал за сегодня
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();
      await vm.setActivityLevel(ActivityLevel.level1);

      // 30 дней диапазона, шаги только за 1 день: (400 + 0×29) / 30 ≈ 13.33.
      expect(vm.avgCaloriesPerDay, closeTo(400 / 30, 1e-6));
    });

    test('smoothedWeightToday returns last EMA point', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      expect(vm.smoothedWeightToday, isNotNull);
      // EMA сошлась к последнему весу 78 (сглаженная < первой точки).
      expect(vm.smoothedWeightToday!, lessThan(80));
      expect(vm.smoothedWeightToday!, greaterThan(77));
    });
  });

  group('permissions (баннер «нет разрешений», 2026-08-26)', () {
    test('denied permissions set permissionsDenied and skip loading', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        health: Health(),
        permissionCheck: (health) async => false,
        autoLoad: false,
      );
      await vm.load();

      expect(vm.permissionsDenied, isTrue);
      expect(vm.error, isNotNull);
      expect(repo.fetchRawDataCallCount, 0);
    });

    test('granted permissions keep permissionsDenied false and load data', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      repo.addExternalWeight(DateTime.now(), 80);
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        health: Health(),
        permissionCheck: (health) async => true,
        autoLoad: false,
      );
      await vm.load();

      expect(vm.permissionsDenied, isFalse);
      expect(vm.error, isNull);
      // Вес + шаги + сон — три батчевых чтения в load().
      expect(repo.fetchRawDataCallCount, 3);
    });

    test('recheckPermissions reloads data after user grants in settings', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      var granted = false;
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        health: Health(),
        permissionCheck: (health) async => granted,
        permissionStatusCheck: (health) async => granted,
        autoLoad: false,
      );
      await vm.load();
      expect(vm.permissionsDenied, isTrue);

      // Пользователь выдал права в системных настройках и вернулся в приложение.
      granted = true;
      await vm.recheckPermissions();

      expect(vm.permissionsDenied, isFalse);
      expect(vm.error, isNull);
      expect(repo.fetchRawDataCallCount, 3);
    });

    test('recheckPermissions does nothing while still denied', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        health: Health(),
        permissionCheck: (health) async => false,
        permissionStatusCheck: (health) async => false,
        autoLoad: false,
      );
      await vm.load();
      await vm.recheckPermissions();

      expect(vm.permissionsDenied, isTrue);
      expect(repo.fetchRawDataCallCount, 0);
    });
  });
}
