import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/repo/mock_health_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Тесты Фазы 2: recordingMethod в mock-точках, write/delete для шагов.
///
/// Спека: `docs/phase2_repository_write_spec.md`, секции 5–7.
void main() {
  late MockHealthRepository mock;
  late HealthDataProcessor processor;

  final testDate = DateKey(DateTime(2026, 1, 15));

  setUp(() {
    mock = MockHealthRepository();
    processor = HealthDataProcessor(appPackageId: kAppPackageId);
  });

  Future<List<HealthDataPoint>> loadStepsPoints(DateTime start, DateTime end) {
    return mock.fetchRawData(types: [HealthDataType.STEPS], startDate: start, endDate: end);
  }

  // ==========================================================================
  // recordingMethod в mock-точках (Фаза 2, секция 5)
  // ==========================================================================

  group('recordingMethod в точках', () {
    test('addManualWeight → manual + наш пакет в sourceName', () {
      mock.addManualWeight(testDate.value, 72.0);
      final point = mock.points.first;
      expect(point.recordingMethod, RecordingMethod.manual);
      expect(point.sourceName, kAppPackageId);
      // A0: на реальном Android sourceId пустой — пакет в sourceName.
      expect(point.sourceId, isEmpty);
    });

    test('addExternalWeight → automatic + внешний пакет', () {
      mock.addExternalWeight(testDate.value, 70.0);
      final point = mock.points.first;
      expect(point.recordingMethod, RecordingMethod.automatic);
      expect(point.sourceName, kExternalSourceId);
    });

    test('addManualSteps → manual + наш пакет в sourceName', () {
      mock.addManualSteps(testDate.value, 10000);
      final point = mock.points.first;
      expect(point.recordingMethod, RecordingMethod.manual);
      expect(point.sourceName, kAppPackageId);
    });

    test('addExternalSteps → automatic + внешний пакет', () {
      mock.addExternalSteps(testDate.value, 8000);
      final point = mock.points.first;
      expect(point.recordingMethod, RecordingMethod.automatic);
      expect(point.sourceName, kExternalSourceId);
    });

    test('writeManualRecord (weight) → manual', () async {
      await mock.writeManualRecord(testDate, MetricType.weight, 72.0);
      final point = mock.points.first;
      expect(point.recordingMethod, RecordingMethod.manual);
      expect(point.sourceName, kAppPackageId);
    });

    test('writeManualRecord (steps) → manual', () async {
      await mock.writeManualRecord(testDate, MetricType.steps, 10000);
      final point = mock.points.first;
      expect(point.recordingMethod, RecordingMethod.manual);
      expect(point.sourceName, kAppPackageId);
    });
  });

  // ==========================================================================
  // write/delete для шагов (контракт репозитория, Фаза 2, секция 5)
  // ==========================================================================

  group('write/delete для шагов', () {
    test('hasManualRecord: true после writeManualRecord', () async {
      await mock.writeManualRecord(testDate, MetricType.steps, 10000);
      expect(await mock.hasManualRecord(testDate, MetricType.steps), isTrue);
    });

    test('hasManualRecord: false без записи', () async {
      expect(await mock.hasManualRecord(testDate, MetricType.steps), isFalse);
    });

    test('hasManualRecord: false после deleteManualRecord', () async {
      await mock.writeManualRecord(testDate, MetricType.steps, 10000);
      await mock.deleteManualRecord(testDate, MetricType.steps);
      expect(await mock.hasManualRecord(testDate, MetricType.steps), isFalse);
    });

    test('writeManualRecord: перезапись существующей ручной записи', () async {
      await mock.writeManualRecord(testDate, MetricType.steps, 10000);
      await mock.writeManualRecord(testDate, MetricType.steps, 12000);

      final points = await mock.fetchRawData(
        types: [HealthDataType.STEPS],
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
      );

      final manualPoints = points
          .where((p) => HealthDataProcessor.sourcePackageOf(p) == kAppPackageId)
          .toList();
      expect(manualPoints.length, 1);
      expect(
        (manualPoints.first.value as NumericHealthValue).numericValue.toInt(),
        12000,
      );
    });

    test('резолюция через writeManualRecord (полный цикл, сырые точки)', () async {
      mock.addExternalSteps(testDate.value, 8000);
      var points = await loadStepsPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      var result = processor.resolveStepsForDate(testDate, points);
      expect(result!.source, DataSource.external);
      expect(result.steps, 8000);

      await mock.writeManualRecord(testDate, MetricType.steps, 10000);
      points = await loadStepsPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      result = processor.resolveStepsForDate(testDate, points);
      expect(result!.source, DataSource.manual);
      expect(result.steps, 10000);

      await mock.deleteManualRecord(testDate, MetricType.steps);
      points = await loadStepsPoints(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      result = processor.resolveStepsForDate(testDate, points);
      expect(result!.source, DataSource.external);
    });
  });

  // ==========================================================================
  // DateKey: startOfDay / endOfDay (Фаза 2)
  // ==========================================================================

  group('DateKey startOfDay / endOfDay', () {
    test('startOfDay — полночь', () {
      final date = DateKey(DateTime(2026, 1, 15, 14, 30));
      expect(date.startOfDay, DateTime(2026, 1, 15));
      expect(date.startOfDay.hour, 0);
      expect(date.startOfDay.minute, 0);
    });

    test('endOfDay — 23:59:59.999', () {
      final date = DateKey(DateTime(2026, 1, 15, 14, 30));
      expect(date.endOfDay.year, 2026);
      expect(date.endOfDay.month, 1);
      expect(date.endOfDay.day, 15);
      expect(date.endOfDay.hour, 23);
      expect(date.endOfDay.minute, 59);
      expect(date.endOfDay.second, 59);
      expect(date.endOfDay.millisecond, 999);
    });
  });

  // ==========================================================================
  // ФАЗА 7, A.7 — ручной «Итог дня» (hasManualNutrition / write / delete)
  // ==========================================================================

  group('«Итог дня» (Фаза 7, A.7)', () {
    test('writeManualNutrition создаёт точку «Итог дня» с макросами, manual', () async {
      await mock.writeManualNutrition(
        testDate,
        calories: 2100,
        protein: 150,
        fat: 70,
        carbs: 220,
      );
      expect(await mock.hasManualNutrition(testDate), isTrue);

      final points = await mock.fetchRawData(
        types: const [HealthDataType.NUTRITION],
        startDate: testDate.value,
        endDate: testDate.value,
      );
      expect(points, hasLength(1));
      expect(points.first.sourceName, kAppPackageId);
      expect(points.first.recordingMethod, RecordingMethod.manual);
      final value = points.first.value as NutritionHealthValue;
      expect(value.name, 'Итог дня');
      expect(value.calories, 2100);
      expect(value.protein, 150);
      expect(value.fat, 70);
      expect(value.carbs, 220);
    });

    test('повторный writeManualNutrition не плодит дубли (delete-then-write, R5)', () async {
      await mock.writeManualNutrition(testDate, calories: 2100);
      await mock.writeManualNutrition(testDate, calories: 1950, protein: 140);

      final points = await mock.fetchRawData(
        types: const [HealthDataType.NUTRITION],
        startDate: testDate.value,
        endDate: testDate.value,
      );
      expect(points, hasLength(1));
      expect((points.first.value as NutritionHealthValue).calories, 1950);
    });

    test('deleteManualNutrition откатывает на внешние данные (Tier 2)', () async {
      mock.addExternalNutrition(testDate.value, calories: 2500);
      await mock.writeManualNutrition(testDate, calories: 2100);
      expect(await mock.hasManualNutrition(testDate), isTrue);

      final withManual = processor.resolveNutritionForDate(
        testDate,
        await mock.fetchRawData(
          types: const [HealthDataType.NUTRITION],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 31),
        ),
      );
      expect(withManual!.source, DataSource.manual);

      await mock.deleteManualNutrition(testDate);
      expect(await mock.hasManualNutrition(testDate), isFalse);

      final rolledBack = processor.resolveNutritionForDate(
        testDate,
        await mock.fetchRawData(
          types: const [HealthDataType.NUTRITION],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 31),
        ),
      );
      expect(rolledBack!.source, DataSource.external);
      expect(rolledBack.calories, 2500);
    });

    test('мок seedPhase7Data детерминирован (A.9)', () {
      final end = DateTime(2026, 7, 24);
      final a = MockHealthRepository()..seedPhase7Data(end: end, days: 30);
      final b = MockHealthRepository()..seedPhase7Data(end: end, days: 30);

      String describe(MockHealthRepository repo) => repo.points
          .map((p) =>
              '${p.type.name}|${p.sourceName}|${p.dateFrom}|${p.value}')
          .join(';');
      expect(describe(a), describe(b));

      // Seed соответствует контракту A.9: 2 дня без питания, BASAL каждый
      // день, HEIGHT 178.
      final nutritionDays = a.points
          .where((p) => p.type == HealthDataType.NUTRITION)
          .map((p) => DateKey(p.dateFrom))
          .toSet();
      expect(nutritionDays.length, 28); // 30 − 2 пустых
      final basalDays = a.points
          .where((p) => p.type == HealthDataType.BASAL_ENERGY_BURNED)
          .map((p) => DateKey(p.dateFrom))
          .toSet();
      expect(basalDays.length, 30);
      final height = processor.resolveHeight(
        a.points.where((p) => p.type == HealthDataType.HEIGHT).toList(),
      );
      expect(height, 178);
    });
  });
}