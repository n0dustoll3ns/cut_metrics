import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/repo/mock_health_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Тесты резолюции приоритета источников (Фаза 1, Definition of Done).
///
/// Сценарии — по спеке `docs/phase1_data_model_spec.md`, раздел 10.
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
      mock.addExternalWeight(testDate.value, 70.0, sourceId: 'com.scale.app');
      mock.addExternalWeight(testDate.value, 71.0, sourceId: 'com.other.app');

      final points = await loadWeightPoints(rangeStart, rangeEnd);
      final result = processor.resolveWeightForDate(testDate, points);

      expect(result, isNotNull);
      expect(result!.source, DataSource.external);
      // last-wins: вторая запись позже по времени (добавлена позже)
      expect(result.weight, 71.0);
    });
  });

  // ==========================================================================
  // ШАГИ — resolveStepsForDate
  // ==========================================================================

  group('resolveStepsForDate', () {
    final rangeStart = DateTime(2026, 1, 1);
    final rangeEnd = DateTime(2026, 1, 31);

    test('(a) только внешние записи (агрегированные) → source: external', () async {
      // Шаги Tier 2 приходят через aggregate(), не через сырые точки
      mock.setAggregateExternalSteps(testDate, 8500);

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final aggregated = await mock.aggregateExternalSteps(testDate);
      final result = processor.resolveStepsForDate(testDate, points, aggregated);

      expect(result, isNotNull);
      expect(result!.source, DataSource.external);
      expect(result.steps, 8500);
    });

    test('(b) только ручная запись → source: manual', () async {
      mock.addManualSteps(testDate.value, 10000);

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final aggregated = await mock.aggregateExternalSteps(testDate);
      final result = processor.resolveStepsForDate(testDate, points, aggregated);

      expect(result, isNotNull);
      expect(result!.source, DataSource.manual);
      expect(result.steps, 10000);
    });

    test('(c) есть обе → побеждает manual, внешние игнорируются', () async {
      mock.addExternalSteps(testDate.value, 8000);
      mock.addManualSteps(testDate.value, 10000);
      mock.setAggregateExternalSteps(testDate, 8000);

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final aggregated = await mock.aggregateExternalSteps(testDate);
      final result = processor.resolveStepsForDate(testDate, points, aggregated);

      expect(result, isNotNull);
      expect(result!.source, DataSource.manual);
      expect(result.steps, 10000);
    });

    test('(d) нет записей → null', () async {
      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final aggregated = await mock.aggregateExternalSteps(testDate);
      final result = processor.resolveStepsForDate(testDate, points, aggregated);

      expect(result, isNull);
    });

    test('(e) несколько внешних источников → не задваивается', () async {
      // Два внешних источника по 5000 шагов каждый.
      // aggregate() должен вернуть одно значение (приоритет ОС), не сумму.
      // Имитируем это через override:
      mock.addExternalSteps(testDate.value, 5000, sourceId: 'com.phone.pedometer');
      mock.addExternalSteps(testDate.value, 5000, sourceId: 'com.watch.app');
      // aggregate() резолвит приоритет — возвращаем 5000, а не 10000
      mock.setAggregateExternalSteps(testDate, 5000);

      final points = await loadStepsPoints(rangeStart, rangeEnd);
      final aggregated = await mock.aggregateExternalSteps(testDate);
      final result = processor.resolveStepsForDate(testDate, points, aggregated);

      expect(result, isNotNull);
      expect(result!.source, DataSource.external);
      expect(result.steps, 5000); // НЕ 10000 — нет задвоения
    });

    test('aggregate вернул null → null', () async {
      final points = <HealthDataPoint>[];
      final result = processor.resolveStepsForDate(testDate, points, null);

      expect(result, isNull);
    });

    test('aggregate вернул 0 → null', () async {
      final points = <HealthDataPoint>[];
      final result = processor.resolveStepsForDate(testDate, points, 0);

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
      mock.setAggregateExternalSteps(testDate, 8000);

      var points = await loadStepsPoints(rangeStart, rangeEnd);
      var aggregated = await mock.aggregateExternalSteps(testDate);
      var result = processor.resolveStepsForDate(testDate, points, aggregated);
      expect(result!.source, DataSource.manual);
      expect(result.steps, 10000);

      // 2. Удаляем ручную
      await mock.deleteManualRecord(testDate, MetricType.steps);

      // 3. Теперь → external (из aggregate)
      points = await loadStepsPoints(rangeStart, rangeEnd);
      aggregated = await mock.aggregateExternalSteps(testDate);
      result = processor.resolveStepsForDate(testDate, points, aggregated);
      expect(result!.source, DataSource.external);
      expect(result.steps, 8000);
    });

    test('шаги: manual → deleteManualRecord → null (нет внешних)', () async {
      // 1. Только ручная → manual
      mock.addManualSteps(testDate.value, 10000);

      var points = await loadStepsPoints(rangeStart, rangeEnd);
      var aggregated = await mock.aggregateExternalSteps(testDate);
      var result = processor.resolveStepsForDate(testDate, points, aggregated);
      expect(result!.source, DataSource.manual);

      // 2. Удаляем ручную
      await mock.deleteManualRecord(testDate, MetricType.steps);

      // 3. Нет данных → null
      points = await loadStepsPoints(rangeStart, rangeEnd);
      aggregated = await mock.aggregateExternalSteps(testDate);
      result = processor.resolveStepsForDate(testDate, points, aggregated);
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
      final manualPoints = points.where((p) => p.sourceId == kAppPackageId).toList();
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
      final day1 = DateKey(DateTime(2026, 1, 10)); // только external (aggregate)
      final day2 = DateKey(DateTime(2026, 1, 11)); // только manual
      final day3 = DateKey(DateTime(2026, 1, 12)); // обе → manual

      mock.setAggregateExternalSteps(day1, 8000);
      mock.addManualSteps(day2.value, 10000);
      mock.addManualSteps(day3.value, 10000);
      mock.setAggregateExternalSteps(day3, 8000);

      final points = await loadStepsPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      final aggregated = <DateKey, int>{
        day1: 8000,
        day3: 8000,
      };
      final result = processor.resolveStepsForAllDates(points, aggregated);

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
  });
}