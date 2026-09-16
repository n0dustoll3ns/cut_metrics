import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/repo/mock_health_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Тесты резолюции приоритета источников (Фаза 1 DoD + Фаза 6, A0/A2/B/C).
///
/// Сценарии — по спекам `docs/phase1_data_model_spec.md` (раздел 10) и
/// `docs/phase6_implementation_task.md` (части A–C). Мок создаёт точки
/// «как на реальном Android»: `sourceId` пустой, пакет — в `sourceName`
/// (итог A0-лога), поэтому все тесты гоняют путь `sourcePackageOf`.
void main() {
  late MockHealthRepository mock;
  late HealthDataProcessor processor;

  // Фикстура: 15 января 2026
  final testDate = DateKey(DateTime(2026, 1, 15));

  setUp(() {
    mock = MockHealthRepository();
    processor = HealthDataProcessor(appPackageId: kAppPackageId);
  });

  // ─── Вспомогательные методы для загрузки сырых точек через мок ──────────────

  /// Загружает сырые точки веса из мока (имитация fetchRawData в реальном репо).
  Future<List<HealthDataPoint>> loadWeightPoints(DateTime start, DateTime end) {
    return mock.fetchRawData(
      types: [HealthDataType.WEIGHT],
      startDate: start,
      endDate: end,
    );
  }

  /// Загружает сырые точки шагов из мока.
  Future<List<HealthDataPoint>> loadStepsPoints(DateTime start, DateTime end) {
    return mock.fetchRawData(
      types: [HealthDataType.STEPS],
      startDate: start,
      endDate: end,
    );
  }

  // ==========================================================================
  // ВЕС — resolveWeightForDate
  // ==========================================================================

  group('resolveWeightForDate', () {
    final rangeStart = DateTime(2026, 1, 1);
    final rangeEnd = DateTime(2026, 1, 31);

    test('(a) только внешние записи → source: external', () async {
      mock.addExternalWeight(testDate.value, 70.5);

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final result = processor.resolveWeightForDate(testDate, points);

      expect(result, isNotNull);
      expect(result!.source, DataSource.external);
      expect(result.weight, 70.5);
      expect(result.date, testDate);
    });

    test('(b) только ручная запись → source: manual', () async {
      mock.addManualWeight(testDate.value, 72.0);

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final result = processor.resolveWeightForDate(testDate, points);

      expect(result, isNotNull);
      expect(result!.source, DataSource.manual);
      expect(result.weight, 72.0);
    });

    test('(c) есть обе → побеждает manual', () async {
      mock.addExternalWeight(testDate.value, 70.5);
      mock.addManualWeight(testDate.value, 72.0);

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final result = processor.resolveWeightForDate(testDate, points);

      expect(result, isNotNull);
      expect(result!.source, DataSource.manual);
      expect(result.weight, 72.0);
    });

    test('(d) нет записей → null', () async {
      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final result = processor.resolveWeightForDate(testDate, points);

      expect(result, isNull);
    });

    test('last-wins: несколько внешних записей → последняя по времени', () async {
      // Две внешние записи в один день, разные источники
      mock.addExternalWeight(testDate.value, 70.0, sourcePackage: 'com.scale.app');
      mock.addExternalWeight(testDate.value, 71.0, sourcePackage: 'com.other.app');

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final result = processor.resolveWeightForDate(testDate, points);

      expect(result, isNotNull);
      expect(result!.source, DataSource.external);
      // last-wins: вторая запись позже по времени (добавлена позже)
      expect(result.weight, 71.0);
      // Фаза 6, C.2: sourcePackage = пакет итоговой точки
      expect(result.sourcePackage, 'com.other.app');
    });
  });

  // ==========================================================================
  // ВЕС — Фаза 6: refused-фильтр и выбор источника
  // ==========================================================================

  group('resolveWeightForDate: решения и выбор источника (Фаза 6)', () {
    final rangeStart = DateTime(2026, 1, 1);
    final rangeEnd = DateTime(2026, 1, 31);

    test('отклонённый источник исключается из резолюции', () async {
      mock.addExternalWeight(testDate.value, 70.0, sourcePackage: 'com.refused.app');

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final decisions = {'com.refused.app': ConfirmDecision.refused};

      expect(
        processor.resolveWeightForDate(testDate, points, decisions: decisions),
        isNull,
      );
    });

    test('отказ одного источника → last-wins среди оставшихся', () async {
      mock.addExternalWeight(testDate.value, 70.0, sourcePackage: 'com.refused.app');
      mock.addExternalWeight(testDate.value, 71.0, sourcePackage: 'com.ok.app');

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final decisions = {'com.refused.app': ConfirmDecision.refused};

      final result = processor.resolveWeightForDate(testDate, points, decisions: decisions);

      expect(result, isNotNull);
      expect(result!.weight, 71.0);
      expect(result.sourcePackage, 'com.ok.app');
    });

    test('подтверждённый источник не исключается (resolves как обычно)', () async {
      mock.addExternalWeight(testDate.value, 70.0, sourcePackage: 'com.ok.app');

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final decisions = {'com.ok.app': ConfirmDecision.confirmed};

      final result = processor.resolveWeightForDate(testDate, points, decisions: decisions);

      expect(result, isNotNull);
      expect(result!.weight, 70.0);
    });

    test('выбран источник → только его точки (last-wins внутри источника)', () async {
      mock.addExternalWeight(testDate.value, 70.0, sourcePackage: 'com.scale.app');
      mock.addExternalWeight(testDate.value, 69.0, sourcePackage: 'com.watch.app');

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final result = processor.resolveWeightForDate(
        testDate,
        points,
        selection: const SourceSelection.app('com.scale.app'),
      );

      expect(result, isNotNull);
      expect(result!.weight, 70.0);
      expect(result.sourcePackage, 'com.scale.app');
    });

    test('выбран источник без данных за дату → null (не фолбэк на другие)', () async {
      mock.addExternalWeight(testDate.value, 70.0, sourcePackage: 'com.scale.app');

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final result = processor.resolveWeightForDate(
        testDate,
        points,
        selection: const SourceSelection.app('com.watch.app'),
      );

      expect(result, isNull);
    });
  });

  // ==========================================================================
  // ШАГИ — resolveStepsForDate
  // ==========================================================================

  group('resolveStepsForDate', () {
    final rangeStart = DateTime(2026, 1, 1);
    final rangeEnd = DateTime(2026, 1, 31);

    test('(a) только внешние записи → source: external, сумма одного источника', () async {
      // Фаза 6, A2: резолюция по сырым точкам, без aggregate-API
      mock.addExternalSteps(testDate.value, 5000, sourcePackage: 'com.phone.pedometer');
      mock.addExternalSteps(testDate.value, 3500, sourcePackage: 'com.phone.pedometer');

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final result = processor.resolveStepsForDate(testDate, points);

      expect(result, isNotNull);
      expect(result!.source, DataSource.external);
      expect(result.steps, 8500);
      expect(result.sourcePackage, 'com.phone.pedometer');
    });

    test('(b) только ручная запись → source: manual', () async {
      mock.addManualSteps(testDate.value, 10000);

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final result = processor.resolveStepsForDate(testDate, points);

      expect(result, isNotNull);
      expect(result!.source, DataSource.manual);
      expect(result.steps, 10000);
      expect(result.sourcePackage, kAppPackageId);
    });

    test('(c) есть обе → побеждает manual, внешние игнорируются', () async {
      mock.addExternalSteps(testDate.value, 8000);
      mock.addManualSteps(testDate.value, 10000);

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final result = processor.resolveStepsForDate(testDate, points);

      expect(result, isNotNull);
      expect(result!.source, DataSource.manual);
      expect(result.steps, 10000);
    });

    test('(d) нет записей → null', () async {
      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final result = processor.resolveStepsForDate(testDate, points);

      expect(result, isNull);
    });

    test('(e) «Авто»: несколько источников → максимальная сумма, не сумма всех', () async {
      // Два внешних источника: телефон 5000, часы 9000 → берём 9000.
      mock.addExternalSteps(testDate.value, 5000, sourcePackage: 'com.phone.pedometer');
      mock.addExternalSteps(testDate.value, 9000, sourcePackage: 'com.watch.app');

      var warned = false;
      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final result = processor.resolveStepsForDate(
        testDate,
        points,
        onWarn: (_) => warned = true,
      );

      expect(result, isNotNull);
      expect(result!.steps, 9000);
      expect(result.sourcePackage, 'com.watch.app');
      // Диагностика выбора: несколько источников → warn (C.2)
      expect(warned, isTrue);
    });

    test('(f) выбран источник → сумма только его точек', () async {
      mock.addExternalSteps(testDate.value, 5000, sourcePackage: 'com.phone.pedometer');
      mock.addExternalSteps(testDate.value, 9000, sourcePackage: 'com.watch.app');

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final result = processor.resolveStepsForDate(
        testDate,
        points,
        selection: const SourceSelection.app('com.phone.pedometer'),
      );

      expect(result, isNotNull);
      expect(result!.steps, 5000);
      expect(result.sourcePackage, 'com.phone.pedometer');
    });

    test('(g) отклонённый источник исключается из резолюции', () async {
      mock.addExternalSteps(testDate.value, 8000, sourcePackage: 'com.refused.app');

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final result = processor.resolveStepsForDate(
        testDate,
        points,
        decisions: {'com.refused.app': ConfirmDecision.refused},
      );

      expect(result, isNull);
    });

    test('(h) отказ одного источника → максимальная сумма среди оставшихся', () async {
      mock.addExternalSteps(testDate.value, 12000, sourcePackage: 'com.refused.app');
      mock.addExternalSteps(testDate.value, 4000, sourcePackage: 'com.phone.pedometer');
      mock.addExternalSteps(testDate.value, 3000, sourcePackage: 'com.phone.pedometer');

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final result = processor.resolveStepsForDate(
        testDate,
        points,
        decisions: {'com.refused.app': ConfirmDecision.refused},
      );

      expect(result, isNotNull);
      expect(result!.steps, 7000);
      expect(result.sourcePackage, 'com.phone.pedometer');
    });

    test('шаги: manual → deleteManualRecord → null (нет внешних)', () async {
      // 1. Только ручная → manual
      mock.addManualSteps(testDate.value, 10000);

      var points = await loadStepsPoints(rangeStart, rangeEnd);
      var result = processor.resolveStepsForDate(testDate, points);
      expect(result!.source, DataSource.manual);

      // 2. Удаляем ручную
      await mock.deleteManualRecord(testDate, MetricType.steps);

      // 3. Нет данных → null
      points = await loadStepsPoints(rangeStart, rangeEnd);
      result = processor.resolveStepsForDate(testDate, points);
      expect(result, isNull);
    });
  });

  // ==========================================================================
  // ОТМЕНА ручной коррекции (delete → откат на external)
  // ==========================================================================

  group('отмена ручной коррекции', () {
    final rangeStart = DateTime(2026, 1, 1);
    final rangeEnd = DateTime(2026, 1, 31);

    test('вес: manual → deleteManualRecord → external', () async {
      // 1. Обе записи → manual
      mock.addExternalWeight(testDate.value, 70.5);
      mock.addManualWeight(testDate.value, 72.0);

      var points = await loadWeightPoints(rangeStart, rangeEnd);
      var result = processor.resolveWeightForDate(testDate, points);
      expect(result!.source, DataSource.manual);
      expect(result.weight, 72.0);

      // 2. Удаляем ручную
      await mock.deleteManualRecord(testDate, MetricType.weight);

      // 3. Теперь → external
      points = await loadWeightPoints(rangeStart, rangeEnd);
      result = processor.resolveWeightForDate(testDate, points);
      expect(result!.source, DataSource.external);
      expect(result.weight, 70.5);
    });

    test('вес: manual → deleteManualRecord → null (нет внешних)', () async {
      // 1. Только ручная → manual
      mock.addManualWeight(testDate.value, 72.0);

      var points = await loadWeightPoints(rangeStart, rangeEnd);
      var result = processor.resolveWeightForDate(testDate, points);
      expect(result!.source, DataSource.manual);

      // 2. Удаляем ручную
      await mock.deleteManualRecord(testDate, MetricType.weight);

      // 3. Нет данных → null
      points = await loadWeightPoints(rangeStart, rangeEnd);
      result = processor.resolveWeightForDate(testDate, points);
      expect(result, isNull);
    });

    test('шаги: manual → deleteManualRecord → external', () async {
      // 1. Обе записи → manual
      mock.addManualSteps(testDate.value, 10000);
      mock.addExternalSteps(testDate.value, 8000);

      var points = await loadStepsPoints(rangeStart, rangeEnd);
      var result = processor.resolveStepsForDate(testDate, points);
      expect(result!.source, DataSource.manual);
      expect(result.steps, 10000);

      // 2. Удаляем ручную
      await mock.deleteManualRecord(testDate, MetricType.steps);

      // 3. Теперь → external (по сырым точкам)
      points = await loadStepsPoints(rangeStart, rangeEnd);
      result = processor.resolveStepsForDate(testDate, points);
      expect(result!.source, DataSource.external);
      expect(result.steps, 8000);
    });

    test('шаги: manual → deleteManualRecord → null (нет внешних)', () async {
      // 1. Только ручная → manual
      mock.addManualSteps(testDate.value, 10000);

      var points = await loadStepsPoints(rangeStart, rangeEnd);
      var result = processor.resolveStepsForDate(testDate, points);
      expect(result!.source, DataSource.manual);

      // 2. Удаляем ручную
      await mock.deleteManualRecord(testDate, MetricType.steps);

      // 3. Нет данных → null
      points = await loadStepsPoints(rangeStart, rangeEnd);
      result = processor.resolveStepsForDate(testDate, points);
      expect(result, isNull);
    });
  });

  // ==========================================================================
  // КОНТРАКТ РЕПОЗИТОРИЯ — hasManualRecord / writeManualRecord
  // ==========================================================================

  group('контракт репозитория (hasManualRecord / writeManualRecord)', () {
    test('hasManualRecord: true после writeManualRecord', () async {
      await mock.writeManualRecord(testDate, MetricType.weight, 72.0);
      expect(await mock.hasManualRecord(testDate, MetricType.weight), isTrue);
    });

    test('hasManualRecord: false без записи', () async {
      expect(await mock.hasManualRecord(testDate, MetricType.weight), isFalse);
    });

    test('hasManualRecord: false после deleteManualRecord', () async {
      await mock.writeManualRecord(testDate, MetricType.weight, 72.0);
      await mock.deleteManualRecord(testDate, MetricType.weight);
      expect(await mock.hasManualRecord(testDate, MetricType.weight), isFalse);
    });

    test('writeManualRecord: перезапись существующей ручной записи', () async {
      await mock.writeManualRecord(testDate, MetricType.weight, 72.0);
      await mock.writeManualRecord(testDate, MetricType.weight, 73.5);

      final points = await mock.fetchRawData(
        types: [HealthDataType.WEIGHT],
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
      );

      // Должна быть только одна ручная запись с новым значением
      // (delete-then-write, A1.1; свой пакет — по sourceName, A0)
      final manualPoints =
          points.where((p) => HealthDataProcessor.sourcePackageOf(p) == kAppPackageId).toList();
      expect(manualPoints.length, 1);
      expect(
        (manualPoints.first.value as NumericHealthValue).numericValue.toDouble(),
        73.5,
      );
    });

    test('резолюция через writeManualRecord (полный цикл)', () async {
      // Внешняя запись
      mock.addExternalWeight(testDate.value, 70.0);
      var points = await loadWeightPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      var result = processor.resolveWeightForDate(testDate, points);
      expect(result!.source, DataSource.external);

      // Записываем ручную → теперь manual
      await mock.writeManualRecord(testDate, MetricType.weight, 72.0);
      points = await loadWeightPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      result = processor.resolveWeightForDate(testDate, points);
      expect(result!.source, DataSource.manual);
      expect(result.weight, 72.0);

      // Удаляем → обратно external
      await mock.deleteManualRecord(testDate, MetricType.weight);
      points = await loadWeightPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      result = processor.resolveWeightForDate(testDate, points);
      expect(result!.source, DataSource.external);
    });
  });

  // ==========================================================================
  // БАТЧЕВАЯ РЕЗОЛЮЦИЯ — resolveWeightForAllDates / resolveStepsForAllDates
  // ==========================================================================

  group('батчевая резолюция на диапазон', () {
    test('вес: несколько дат с разными источниками', () async {
      final day1 = DateKey(DateTime(2026, 1, 10)); // только внешняя
      final day2 = DateKey(DateTime(2026, 1, 11)); // только ручная
      final day3 = DateKey(DateTime(2026, 1, 12)); // обе → manual
      // day4 (13) — нет данных

      mock.addExternalWeight(day1.value, 70.0);
      mock.addManualWeight(day2.value, 71.0);
      mock.addExternalWeight(day3.value, 70.5);
      mock.addManualWeight(day3.value, 72.0);

      final points = await loadWeightPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      final result = processor.resolveWeightForAllDates(points);

      expect(result.length, 3); // day4 нет
      expect(result[day1]?.source, DataSource.external);
      expect(result[day1]?.weight, 70.0);
      expect(result[day2]?.source, DataSource.manual);
      expect(result[day2]?.weight, 71.0);
      expect(result[day3]?.source, DataSource.manual);
      expect(result[day3]?.weight, 72.0);
    });

    test('шаги: несколько дат с разными источниками', () async {
      final day1 = DateKey(DateTime(2026, 1, 10)); // только external (сырые точки)
      final day2 = DateKey(DateTime(2026, 1, 11)); // только manual
      final day3 = DateKey(DateTime(2026, 1, 12)); // обе → manual

      mock.addExternalSteps(day1.value, 8000);
      mock.addManualSteps(day2.value, 10000);
      mock.addManualSteps(day3.value, 10000);
      mock.addExternalSteps(day3.value, 8000);

      final points = await loadStepsPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      final result = processor.resolveStepsForAllDates(points);

      expect(result.length, 3);
      expect(result[day1]?.source, DataSource.external);
      expect(result[day1]?.steps, 8000);
      expect(result[day2]?.source, DataSource.manual);
      expect(result[day2]?.steps, 10000);
      expect(result[day3]?.source, DataSource.manual);
      expect(result[day3]?.steps, 10000);
    });
  });

  // ==========================================================================
  // СПИСОК НАЙДЕННЫХ ИСТОЧНИКОВ — externalSources (Фаза 6, C.1)
  // ==========================================================================

  group('externalSources (Фаза 6, C.1)', () {
    test('уникальные пакеты без нашего, отсортированы', () async {
      mock.addExternalWeight(DateTime(2026, 1, 15), 70.0, sourcePackage: 'com.watch.app');
      mock.addExternalWeight(DateTime(2026, 1, 15), 70.5, sourcePackage: 'com.scale.app');
      mock.addExternalWeight(DateTime(2026, 1, 16), 71.0, sourcePackage: 'com.watch.app');
      mock.addManualWeight(DateTime(2026, 1, 17), 72.0);

      final points = await loadWeightPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      expect(processor.externalSources(points), ['com.scale.app', 'com.watch.app']);
    });

    test('пустой список точек → пустой список источников', () {
      expect(processor.externalSources([]), isEmpty);
    });
  });

  // ==========================================================================
  // МОДЕЛИ — == / hashCode
  // ==========================================================================

  group('WeightDay == / hashCode', () {
    test('одинаковые значения → равны', () {
      final a = WeightDay(
        date: DateKey(DateTime(2026, 1, 15)),
        weight: 70.5,
        source: DataSource.manual,
      );
      final b = WeightDay(
        date: DateKey(DateTime(2026, 1, 15)),
        weight: 70.5,
        source: DataSource.manual,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('разный источник → не равны', () {
      final a = WeightDay(
        date: DateKey(DateTime(2026, 1, 15)),
        weight: 70.5,
        source: DataSource.manual,
      );
      final b = WeightDay(
        date: DateKey(DateTime(2026, 1, 15)),
        weight: 70.5,
        source: DataSource.external,
      );
      expect(a, isNot(equals(b)));
    });

    test('разный sourcePackage → не равны (Фаза 6)', () {
      final a = WeightDay(
        date: DateKey(DateTime(2026, 1, 15)),
        weight: 70.5,
        source: DataSource.external,
        sourcePackage: 'com.scale.app',
      );
      final b = WeightDay(
        date: DateKey(DateTime(2026, 1, 15)),
        weight: 70.5,
        source: DataSource.external,
        sourcePackage: 'com.watch.app',
      );
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(b.hashCode));
    });
  });

  // ==========================================================================
  // ФАЗА 7, A.6 — резолюция питания «один источник на день»
  // ==========================================================================

  group('resolveNutritionForAllDates (Фаза 7, A.6)', () {
    final day1 = DateKey(DateTime(2026, 1, 10));
    final day2 = DateKey(DateTime(2026, 1, 11));
    final day3 = DateKey(DateTime(2026, 1, 12));

    Future<List<HealthDataPoint>> loadNutrition() => mock.fetchRawData(
          types: const [HealthDataType.NUTRITION],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 31),
        );

    test('(a) внешние записи → external, приёмы суммируются, макросы тоже', () async {
      mock.addExternalNutrition(day1.value, calories: 600, protein: 30, fat: 20, carbs: 60);
      mock.addExternalNutrition(day1.value, calories: 400, protein: 10, fat: 5, carbs: 50);

      final result = processor.resolveNutritionForAllDates(await loadNutrition());
      expect(result[day1]!.source, DataSource.external);
      expect(result[day1]!.calories, 1000);
      expect(result[day1]!.protein, 40);
      expect(result[day1]!.fat, 25);
      expect(result[day1]!.carbs, 110);
      expect(result[day1]!.sourcePackage, kNutritionSourceId);
    });

    test('(b) наш «Итог дня» побеждает (Tier 1)', () async {
      mock.addExternalNutrition(day1.value, calories: 2500);
      mock.addManualNutrition(day1.value, calories: 2100, protein: 150, fat: 70, carbs: 220);

      final result = processor.resolveNutritionForAllDates(await loadNutrition());
      expect(result[day1]!.source, DataSource.manual);
      expect(result[day1]!.calories, 2100);
      expect(result[day1]!.sourcePackage, kAppPackageId);
    });

    test('(c) день без записей → нет в результате («нет данных ≠ 0»)', () async {
      mock.addExternalNutrition(day1.value, calories: 2000);
      // day2 — без записей
      final result = processor.resolveNutritionForAllDates(await loadNutrition());
      expect(result.containsKey(day2), isFalse);
      expect(result.length, 1);
    });

    test('(d) авто = наибольшее покрытие дней, НЕ максимальная сумма', () async {
      // A: 3 дня по скромным калориям; B: 1 день с огромной суммой.
      for (final d in [day1, day2, day3]) {
        mock.addExternalNutrition(d.value, calories: 800, sourcePackage: 'com.tracker.a');
      }
      mock.addExternalNutrition(day1.value, calories: 5000, sourcePackage: 'com.tracker.b');

      final result = processor.resolveNutritionForAllDates(await loadNutrition());
      // День с обоими источниками → победитель A (покрытие), а не B (сумма).
      expect(result[day1]!.sourcePackage, 'com.tracker.a');
      expect(result[day1]!.calories, 800);
      expect(result[day2]!.sourcePackage, 'com.tracker.a');
      expect(result.length, 3);
    });

    test('(e) равное покрытие → больше записей побеждает', () async {
      // A: 1 день, 2 записи; B: 1 день, 1 запись с большей суммой.
      mock.addExternalNutrition(day1.value, calories: 400, sourcePackage: 'com.tracker.a');
      mock.addExternalNutrition(day1.value, calories: 400, sourcePackage: 'com.tracker.a');
      mock.addExternalNutrition(day1.value, calories: 5000, sourcePackage: 'com.tracker.b');

      final result = processor.resolveNutritionForAllDates(await loadNutrition());
      expect(result[day1]!.sourcePackage, 'com.tracker.a');
      expect(result[day1]!.calories, 800);
    });

    test('(f) равное покрытие и записи → большая сумма калорий', () async {
      mock.addExternalNutrition(day1.value, calories: 900, sourcePackage: 'com.tracker.a');
      mock.addExternalNutrition(day1.value, calories: 1000, sourcePackage: 'com.tracker.b');

      final result = processor.resolveNutritionForAllDates(await loadNutrition());
      expect(result[day1]!.sourcePackage, 'com.tracker.b');
    });

    test('(g) refused-источник исключается из резолюции', () async {
      mock.addExternalNutrition(day1.value, calories: 5000, sourcePackage: 'com.tracker.b');
      final points = await loadNutrition();
      final result = processor.resolveNutritionForAllDates(
        points,
        decisions: {'com.tracker.b': ConfirmDecision.refused},
      );
      expect(result.containsKey(day1), isFalse);
    });

    test('(h) выбранный источник → только его точки, без фолбэка', () async {
      mock.addExternalNutrition(day1.value, calories: 800, sourcePackage: 'com.tracker.a');
      mock.addExternalNutrition(day2.value, calories: 3000, sourcePackage: 'com.tracker.b');

      final points = await loadNutrition();
      final result = processor.resolveNutritionForAllDates(
        points,
        selection: const SourceSelection.app('com.tracker.a'),
      );
      expect(result[day1]!.calories, 800);
      expect(result.containsKey(day2), isFalse); // не «Авто» — фолбэка нет
    });

    test('(i) макрос null, если ни одна запись победителя его не отдаёт', () async {
      mock.addExternalNutrition(day1.value, calories: 600, protein: 30); // без жиров/углеводов
      final result = processor.resolveNutritionForAllDates(await loadNutrition());
      expect(result[day1]!.protein, 30);
      expect(result[day1]!.fat, isNull);
      expect(result[day1]!.carbs, isNull);
    });

    test('(j) несколько источников в дне → onWarn', () async {
      mock.addExternalNutrition(day1.value, calories: 800, sourcePackage: 'com.tracker.a');
      mock.addExternalNutrition(day2.value, calories: 800, sourcePackage: 'com.tracker.a');
      mock.addExternalNutrition(day1.value, calories: 500, sourcePackage: 'com.tracker.b');

      final warns = <String>[];
      final result = processor.resolveNutritionForAllDates(
        await loadNutrition(),
        onWarn: warns.add,
      );
      expect(result[day1]!.sourcePackage, 'com.tracker.a');
      expect(warns, hasLength(1)); // только day1 (day2 — один источник)
      expect(warns.single, contains('питание'));
    });
  });

  // ==========================================================================
  // ФАЗА 7, A.4 — BASAL / HEIGHT (чтение HC-значений)
  // ==========================================================================

  group('BASAL / HEIGHT (Фаза 7, A.4)', () {
    final day1 = DateKey(DateTime(2026, 1, 10));
    final day2 = DateKey(DateTime(2026, 1, 11));

    Future<List<HealthDataPoint>> loadBasal() => mock.fetchRawData(
          types: const [HealthDataType.BASAL_ENERGY_BURNED],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 31),
        );

    test('resolveBasalForAllDates: last-wins за день', () async {
      mock.addBasal(day1.value, 1600);
      mock.addBasal(day1.value, 1700);
      mock.addBasal(day2.value, 1650);

      final result = processor.resolveBasalForAllDates(await loadBasal());
      expect(result[day1], 1700);
      expect(result[day2], 1650);
      expect(result.length, 2);
    });

    test('resolveHeight: last-wins по всему диапазону', () async {
      mock.addHeight(DateTime(2025, 6, 1), 177);
      mock.addHeight(DateTime(2026, 1, 5), 178);

      final points = await mock.fetchRawData(
        types: const [HealthDataType.HEIGHT],
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2026, 1, 31),
      );
      expect(processor.resolveHeight(points), 178);
    });
  });

  // ==========================================================================
  // ФАЗА 7, A.4–A.5 — каскад BMR и расход по дням
  // ==========================================================================

  group('computeExpenditures (Фаза 7, A.4–A.5)', () {
    final day0 = DateKey(DateTime(2026, 1, 9)); // до первой записи веса
    final day1 = DateKey(DateTime(2026, 1, 10)); // вес появился
    final day2 = DateKey(DateTime(2026, 1, 11));
    final start = DateKey(DateTime(2026, 1, 9));
    final end = DateKey(DateTime(2026, 1, 11));

    // Вес 80 кг с day1 (вес «на дату» = последняя запись ≤ дата).
    final weightCache = <DateKey, WeightDay>{
      day1: WeightDay(date: day1, weight: 80, source: DataSource.external),
    };

    test('1) ручной BMR = константа на все дни (даже до первой записи веса)', () {
      const profile = ExpenditureProfile(
        bmrMode: BmrMode.manual,
        bmrManualKcal: 1500,
      );
      final result = processor.computeExpenditures(
        weightCache: weightCache,
        stepsCache: const {},
        basalCache: const {},
        profile: profile,
        start: start,
        end: end,
      );
      expect(result[day0]!.bmrKcal, 1500);
      expect(result[day1]!.bmrKcal, 1500);
      expect(result.length, 3);
    });

    test('2) HC BASAL на день → BMR из HC', () {
      final result = processor.computeExpenditures(
        weightCache: weightCache,
        stepsCache: const {},
        basalCache: {day2: 1670.0},
        profile: const ExpenditureProfile(),
        start: start,
        end: end,
      );
      // day0/day1: нет HC, профиль пуст → нет расхода;
      // day2: HC BASAL есть → расход есть даже без профиля и веса.
      expect(result.containsKey(day0), isFalse);
      expect(result.containsKey(day1), isFalse);
      expect(result[day2]!.bmrKcal, 1670);
    });

    test('3) Mifflin заполняет день без HC (профиль полон + вес на дату)', () {
      const profile = ExpenditureProfile(
        sex: EnergySex.male,
        birthYear: 1990,
        heightCm: 178,
      );
      final result = processor.computeExpenditures(
        weightCache: weightCache,
        stepsCache: const {},
        basalCache: const {},
        profile: profile,
        start: start,
        end: end,
      );
      // day0: до первой записи веса → Mifflin невозможен → нет расхода.
      expect(result.containsKey(day0), isFalse);
      // day1: вес 80, возраст 2026−1990=36 → 10*80+6.25*178−5*36+5 = 1737.5.
      expect(result[day1]!.bmrKcal, closeTo(1737.5, 1e-9));
    });

    test('4) неполный профиль → Mifflin нет (только ручной/HC)', () {
      final result = processor.computeExpenditures(
        weightCache: weightCache,
        stepsCache: const {},
        basalCache: const {},
        profile: const ExpenditureProfile(sex: EnergySex.male, heightCm: 178), // нет года
        start: start,
        end: end,
      );
      expect(result, isEmpty);
    });

    test('5) шаги: шаги × вес × 0.0004 (нетто) + вес «на дату» префиксом', () {
      const profile = ExpenditureProfile(bmrMode: BmrMode.manual, bmrManualKcal: 1500);
      final stepsCache = <DateKey, StepsDay>{
        day1: StepsDay(date: day1, steps: 10000, source: DataSource.external),
        day2: StepsDay(date: day2, steps: 5000, source: DataSource.external),
      };
      final result = processor.computeExpenditures(
        weightCache: weightCache,
        stepsCache: stepsCache,
        basalCache: const {},
        profile: profile,
        start: start,
        end: end,
      );
      expect(result[day1]!.stepsKcal, closeTo(10000 * 80 * 0.0004, 1e-9)); // 320
      expect(result[day2]!.stepsKcal, closeTo(5000 * 80 * 0.0004, 1e-9)); // 160
      expect(result[day0]!.stepsKcal, 0); // дня в кеше шагов нет
    });

    ExpenditureDay expForDay1(ExpenditureProfile profile) =>
        processor.computeExpenditures(
          weightCache: weightCache,
          stepsCache: const {},
          basalCache: const {},
          profile: profile,
          start: day1,
          end: day1,
        )[day1]!;

    test('6) силовые: MET умеренная/тяжёлая/своя сессия (нетто −1 MET)', () {
      // Умеренная: (3.5−1) × 80 × 1ч × 3/7.
      final moderate = expForDay1(const ExpenditureProfile(
        bmrMode: BmrMode.manual,
        bmrManualKcal: 1500,
        trainingFreqPerWeek: 3,
      ));
      expect(moderate.trainingKcal, closeTo(2.5 * 80 * 1 * 3 / 7, 1e-9));

      // Тяжёлая: (6.0−1) × 80 × 1.5ч × 2/7.
      final heavy = expForDay1(const ExpenditureProfile(
        bmrMode: BmrMode.manual,
        bmrManualKcal: 1500,
        trainingFreqPerWeek: 2,
        trainingDurationMin: 90,
        trainingIntensity: TrainingIntensity.heavy,
      ));
      expect(heavy.trainingKcal, closeTo(5.0 * 80 * 1.5 * 2 / 7, 1e-9));

      // Своя сессия не зависит от веса: 300 × 4/7.
      final own = expForDay1(const ExpenditureProfile(
        bmrMode: BmrMode.manual,
        bmrManualKcal: 1500,
        trainingFreqPerWeek: 4,
        trainingKcalPerSession: 300,
      ));
      expect(own.trainingKcal, closeTo(300 * 4 / 7, 1e-9));
    });

    test('7) бытовой: дефолт 200 и оверрайд; total = сумма 4 компонентов', () {
      final result = expForDay1(const ExpenditureProfile(
        bmrMode: BmrMode.manual,
        bmrManualKcal: 1500,
        householdKcal: 250,
      ));
      expect(result.householdKcal, 250);
      expect(result.total, 1500 + 0 + 0 + 250);

      final defaults = expForDay1(
        const ExpenditureProfile(bmrMode: BmrMode.manual, bmrManualKcal: 1500),
      );
      expect(defaults.householdKcal, ExpenditureConfig.defaultHouseholdKcal);
    });
  });

  // ==========================================================================
  // ФАЗА 7, A.3 / §0 п. 13 — формулы ExpenditureConfig
  // ==========================================================================

  group('ExpenditureConfig (Фаза 7, A.3)', () {
    test('Mifflin-St Jeor: М (80 кг, 178 см, 36 лет) = 1737.5', () {
      expect(
        mifflinStJeor(sex: EnergySex.male, weightKg: 80, heightCm: 178, ageYears: 36),
        closeTo(1737.5, 1e-9),
      );
    });

    test('Mifflin-St Jeor: Ж = М − 166', () {
      final m = mifflinStJeor(sex: EnergySex.male, weightKg: 70, heightCm: 170, ageYears: 30);
      final f = mifflinStJeor(sex: EnergySex.female, weightKg: 70, heightCm: 170, ageYears: 30);
      expect(m - f, closeTo(166, 1e-9));
    });

    test('целевой дефицит: 70 кг × 0.8%/нед → −616 ккал/день', () {
      expect(ExpenditureConfig.targetDeficitKcalPerDay(70, 0.8), closeTo(616, 1e-9));
    });

    test('дельта v2: вес × |цель−факт| × 11, коридор 50–300, округление до 10', () {
      // 80 кг × 1.0 п.п. × 11 = 880 → 300 (потолок).
      expect(ExpenditureConfig.recommendationDeltaKcal(80, 1.0, 0.0), 300);
      // 80 кг × 0.3 × 11 = 264 → 260.
      expect(ExpenditureConfig.recommendationDeltaKcal(80, 0.5, 0.8), 260);
      // 60 кг × 0.05 × 11 = 33 → 50 (пол).
      expect(ExpenditureConfig.recommendationDeltaKcal(60, 0.8, 0.75), 50);
      // 75 кг × 0.5 × 11 = 412.5 → 300.
      expect(ExpenditureConfig.recommendationDeltaKcal(75, 1.2, 0.7), 300);
    });
  });
}