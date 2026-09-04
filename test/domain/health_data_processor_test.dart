import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/source_selection.dart';
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
}