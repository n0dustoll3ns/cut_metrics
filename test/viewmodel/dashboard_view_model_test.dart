import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
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

      // Вес + шаги + сон + питание + BASAL + рост = 6 батчевых чтений
      // (Фаза 7 добавила NUTRITION/BASAL/HEIGHT), aggregate-API удалены.
      expect(repo.fetchRawDataCallCount, 6);

      // Шаги за сегодня = 5000 (последний день) из сырых точек.
      expect(vm.getResolvedValue(DateKey(now), MetricType.steps)!.value, 5000);
    });

    test('load() makes exactly 6 fetchRawData calls (+ nutrition/basal/height)', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);

      repo.fetchRawDataCallCount = 0;
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();

      // WEIGHT + STEPS + SLEEP + NUTRITION + BASAL + HEIGHT = 6 (Фаза 5 + 7).
      expect(repo.fetchRawDataCallCount, 6);
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
      expect(repo2.fetchRawDataCallCount, 6);

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

    test('avgSteps counts days with records, «сегодня» исключён (A.8)', () async {
      await setupViewModel(externalWeights: [80]);

      final now = DateTime.now();
      repo.addExternalSteps(now.subtract(const Duration(days: 1)), 10000);
      repo.addExternalSteps(now.subtract(const Duration(days: 2)), 6000);
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();

      expect(vm.avgSteps, 8000);
    });

    test('avgExpenditure is null when BMR not resolvable (no profile/basal)', () async {
      await setupViewModel(); // веса нет, профиль пуст, BASAL нет
      expect(vm.avgExpenditure, isNull);
      expect(vm.needsProfileHint, isTrue);
    });

    test('avgExpenditure = Mifflin BMR + steps + household (profile set)', () async {
      const profile = ExpenditureProfile(
        sex: EnergySex.male,
        birthYear: 1990,
        heightCm: 178,
      );
      await setupViewModel(externalWeights: [80]); // вес 80 кг за сегодня
      await vm.setEnergyProfile(profile);

      final now = DateTime.now();
      repo.addExternalSteps(now.subtract(const Duration(days: 1)), 10000);
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();
      await vm.setEnergyProfile(profile);

      // Mifflin (80 кг, 178 см, возраст = год − 1990): 1737.5 при 2026 году.
      final age = DateTime.now().year - 1990;
      final bmr = 10 * 80 + 6.25 * 178 - 5 * age + 5;
      // Расход есть у дней с весом «на дату» (только сегодня, вес один за
      // сегодня) → в среднем (без «сегодня») дней с расходом нет → null.
      expect(vm.expenditureFor(DateKey(now)), isNotNull);
      expect(vm.avgExpenditure, isNull);

      // Добавляем вес и за вчера — расход за вчера появляется в среднем.
      repo.addExternalWeight(now.subtract(const Duration(days: 1)), 80);
      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();
      await vm.setEnergyProfile(profile);

      final yesterday = DateKey(now.subtract(const Duration(days: 1)));
      final exp = vm.expenditureFor(yesterday)!;
      expect(exp.bmrKcal, closeTo(bmr, 1e-6));
      expect(exp.stepsKcal, closeTo(10000 * 80 * 0.0004, 1e-6)); // 320
      expect(exp.trainingKcal, 0); // частота 0
      expect(exp.householdKcal, 200);
      // Средний расход = расход за вчера (единственный день без «сегодня»).
      expect(vm.avgExpenditure, closeTo(exp.total, 1e-6));
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
      // Вес + шаги + сон + питание + BASAL + рост — шесть батчевых чтений.
      expect(repo.fetchRawDataCallCount, 6);
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
      expect(repo.fetchRawDataCallCount, 6);
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

  // ==========================================================================
  // ФАЗА 7 — питание, расход, энергостаты
  // ==========================================================================

  group('Фаза 7: питание и расход', () {
    test('load() резолвит питание/BASAL/рост в кеши (HC-префилл роста)', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo.addExternalWeight(now, 80);
      repo.addExternalNutrition(now.subtract(const Duration(days: 1)), calories: 2000);
      repo.addExternalNutrition(now.subtract(const Duration(days: 2)), calories: 2200);
      repo.addBasal(now.subtract(const Duration(days: 1)), 1670);
      repo.addHeight(now.subtract(const Duration(days: 100)), 178);

      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();

      final yesterday = DateKey(now.subtract(const Duration(days: 1)));
      expect(vm.nutritionFor(yesterday)!.calories, 2000);
      expect(vm.nutritionFor(yesterday)!.source, DataSource.external);
      expect(vm.expenditureFor(yesterday)!.bmrKcal, 1670); // каскад: HC BASAL
      expect(vm.effectiveHeightCm, 178); // префилл из HC
      expect(vm.getResolvedValue(yesterday, MetricType.nutrition)!.value, 2000);
    });

    test('submitManualNutrition: итог дня пишется и побеждает (bool)', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo.addExternalNutrition(now, calories: 2500);
      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();

      final today = DateKey(now);
      expect(vm.nutritionFor(today)!.source, DataSource.external);
      final ok = await vm.submitManualNutrition(
        today,
        calories: 2100,
        protein: 150,
        fat: 70,
        carbs: 220,
      );
      expect(ok, isTrue);
      final n = vm.nutritionFor(today)!;
      expect(n.source, DataSource.manual);
      expect(n.calories, 2100);
      expect(n.protein, 150);
    });

    test('cancelManualNutrition: откат на внешние данные', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo.addExternalNutrition(now, calories: 2500);
      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();

      final today = DateKey(now);
      await vm.submitManualNutrition(today, calories: 2100);
      expect(await vm.cancelManualNutrition(today), isTrue);
      expect(vm.nutritionFor(today)!.source, DataSource.external);
      expect(vm.nutritionFor(today)!.calories, 2500);
    });

    test('перерезолюция питания из сырых точек (refuse, без похода в HC)', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo.addExternalNutrition(
        now.subtract(const Duration(days: 1)),
        calories: 2000,
        sourcePackage: 'com.myfitnesspal.android',
      );
      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();

      final calls = repo.fetchRawDataCallCount;
      await vm.refuseSource(MetricType.nutrition, 'com.myfitnesspal.android');
      expect(repo.fetchRawDataCallCount, calls); // обращений к репозиторию нет
      expect(vm.nutritionFor(DateKey(now.subtract(const Duration(days: 1)))), isNull);
      expect(
        vm.isSourceRefused(DateKey(now.subtract(const Duration(days: 1))), MetricType.nutrition),
        isTrue,
      );
    });

    test('avgCaloriesIn/avgMacros — по дням с приходом, «сегодня» исключён', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo.addExternalNutrition(now.subtract(const Duration(days: 1)),
          calories: 2000, protein: 100, fat: 50, carbs: 200);
      repo.addExternalNutrition(now.subtract(const Duration(days: 2)),
          calories: 2400, protein: 140, fat: 70, carbs: 220);
      repo.addExternalNutrition(now, calories: 9999); // сегодня — не в среднем
      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();

      expect(vm.avgCaloriesIn, 2200);
      expect(vm.avgMacros!.protein, 120);
      expect(vm.avgMacros!.fat, 60);
      expect(vm.avgMacros!.carbs, 210);
      expect(vm.intakeDaysInRange, 2);
    });

    test('balanceData: дни только с приходом И расходом; цель −N по весу', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo.addExternalWeight(now.subtract(const Duration(days: 2)), 70);
      repo.addExternalNutrition(now.subtract(const Duration(days: 1)), calories: 2000);
      repo.addExternalNutrition(now.subtract(const Duration(days: 2)), calories: 2600);
      repo.addExternalNutrition(now, calories: 1500); // сегодня — не выводится
      repo.addBasal(now, 1800); // сегодня — не выводится
      repo.addBasal(now.subtract(const Duration(days: 1)), 1800);
      repo.addBasal(now.subtract(const Duration(days: 2)), 1800);
      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();

      final balances = vm.balanceData;
      // «Сегодня» исключён (правило вывода «за вчера», 2026-09-16).
      expect(balances.any((b) => b.date == DateKey(now)), isFalse);
      expect(balances.length, 2);
      final day2 = balances.firstWhere(
        (b) => b.date == DateKey(now.subtract(const Duration(days: 2))),
      );
      // 2600 − (1800 + 0 шагов + 0 силовых + 200 быт) = 600 (профицит).
      expect(day2.balance, 600);
      // Цель: 70 × 0.8% × 11 = 616.
      expect(vm.targetDeficitKcalPerDay, closeTo(616, 1e-9));
    });

    test('computeWeeklyEnergyStats: окно без «сегодня», null при <2 дней', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo.addExternalWeight(now.subtract(const Duration(days: 3)), 70);
      repo.addExternalNutrition(now.subtract(const Duration(days: 1)), calories: 2000);
      repo.addExternalNutrition(now.subtract(const Duration(days: 2)), calories: 2400);
      repo.addBasal(now.subtract(const Duration(days: 1)), 1800);
      repo.addBasal(now.subtract(const Duration(days: 2)), 1800);
      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();

      final stats = vm.computeWeeklyEnergyStats();
      expect(stats, isNotNull);
      expect(stats!.intakeDays, 2);
      expect(stats.avgIntake, 2200);
      expect(stats.avgExpenditure, 2000); // 1800 + 200 быт, шагов нет
      expect(stats.avgBalance, 200);
      expect(stats.expectedKgPerWeek, closeTo(200 * 7 / 7700, 1e-9));

      // Один день с приходом → null.
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      repo.addExternalNutrition(now.subtract(const Duration(days: 1)), calories: 2000);
      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();
      expect(vm.computeWeeklyEnergyStats(), isNull);
    });
  });

    test('avgSteps: данные до 5+-дневного пропуска не входят (2026-09-16)', () async {
      repo = MockHealthRepository();
      processor = HealthDataProcessor(appPackageId: kAppPackageId);
      final now = DateTime.now();
      repo.addExternalSteps(now.subtract(const Duration(days: 1)), 10000);
      repo.addExternalSteps(now.subtract(const Duration(days: 2)), 8000);
      // Пропуск −3..−7 (5 пустых дней): старые записи не в среднем.
      repo.addExternalSteps(now.subtract(const Duration(days: 8)), 2000);
      repo.addExternalSteps(now.subtract(const Duration(days: 9)), 4000);
      vm = DashboardViewModel(repository: repo, processor: processor, autoLoad: false);
      await vm.load();

      expect(vm.avgSteps, 9000); // (10000 + 8000) / 2
    });
}
