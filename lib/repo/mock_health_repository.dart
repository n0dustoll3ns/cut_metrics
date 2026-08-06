import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/repo/health_repository.dart';
import 'package:health/health.dart';

/// Идентификатор пакета приложения — определяет Tier 1 записи.
const kAppPackageId = 'com.example.cut_metrics';

/// Внешний источник по умолчанию для мока.
const kExternalSourceId = 'com.google.android.apps.fitness';

/// Mock-реализация [HealthRepository] для юнит-тестов.
///
/// В отличие от реального репозитория, хранит данные в памяти и позволяет
/// тестам напрямую управлять содержимым через методы `add*`.
///
/// Ключевое: генерирует записи с разным `sourceId` (пакет приложения / внешние),
/// что необходимо для тестирования резолюции приоритета источников.
class MockHealthRepository implements HealthRepository {
  /// Идентификатор пакета приложения — определяет Tier 1.
  final String appPackageId;

  /// Внутреннее хранилище всех точек данных.
  final List<HealthDataPoint> _points = [];

  /// Переопределённые результаты `aggregateExternalSteps` для тестов.
  ///
  /// Если для даты задано значение — возвращается оно.
  /// Иначе — авто-расчёт из [_points].
  final Map<DateKey, int> _aggregateStepsOverride = {};

  MockHealthRepository({this.appPackageId = kAppPackageId});

  // ─── Управление данными для тестов ──────────────────────────────────────────

  /// Добавляет точку напрямую (низкоуровневый API для тестов).
  void addPoint(HealthDataPoint point) => _points.add(point);

  /// Добавляет внешнюю запись веса (Tier 2).
  void addExternalWeight(DateTime date, double weight, {String? sourceId}) {
    addPoint(_makeWeightPoint(date, weight, sourceId ?? kExternalSourceId));
  }

  /// Добавляет ручную запись веса (Tier 1).
  void addManualWeight(DateTime date, double weight) {
    addPoint(_makeWeightPoint(date, weight, appPackageId));
  }

  /// Добавляет внешнюю запись шагов (Tier 2).
  void addExternalSteps(DateTime date, int steps, {String? sourceId}) {
    addPoint(_makeStepsPoint(date, steps, sourceId ?? kExternalSourceId));
  }

  /// Добавляет ручную запись шагов (Tier 1).
  void addManualSteps(DateTime date, int steps) {
    addPoint(_makeStepsPoint(date, steps, appPackageId));
  }

  /// Переопределяет результат `aggregateExternalSteps` для конкретной даты.
  ///
  /// Позволяет тесту напрямую задать «агрегированное» значение,
  /// имитируя результат нативного Health Connect `aggregate()`.
  void setAggregateExternalSteps(DateKey date, int steps) {
    _aggregateStepsOverride[date] = steps;
  }

  /// Очищает все данные (для изоляции тестов).
  void clear() {
    _points.clear();
    _aggregateStepsOverride.clear();
  }

  // ─── Реализация HealthRepository ────────────────────────────────────────────

  @override
  Future<bool> hasManualRecord(DateKey date, MetricType type) async {
    final healthType = _toHealthDataType(type);
    return _points.any(
      (p) => p.sourceId == appPackageId && p.type == healthType && DateKey(p.dateFrom) == date,
    );
  }

  @override
  Future<void> writeManualRecord(DateKey date, MetricType type, num value) async {
    final healthType = _toHealthDataType(type);
    // Удаляем существующую ручную запись на эту дату (перезапись).
    _points.removeWhere(
      (p) => p.sourceId == appPackageId && p.type == healthType && DateKey(p.dateFrom) == date,
    );
    final point = _makePoint(date.value, healthType, value, appPackageId);
    _points.add(point);
  }

  @override
  Future<void> deleteManualRecord(DateKey date, MetricType type) async {
    final healthType = _toHealthDataType(type);
    _points.removeWhere(
      (p) => p.sourceId == appPackageId && p.type == healthType && DateKey(p.dateFrom) == date,
    );
  }

  @override
  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return _points.where((p) {
      if (!types.contains(p.type)) return false;
      final dayStart = DateTime(p.dateFrom.year, p.dateFrom.month, p.dateFrom.day);
      final s = DateTime(startDate.year, startDate.month, startDate.day);
      final e = DateTime(endDate.year, endDate.month, endDate.day);
      return !dayStart.isBefore(s) && !dayStart.isAfter(e);
    }).toList();
  }

  @override
  Future<int?> aggregateExternalSteps(DateKey date) async {
    // Если тест задал override — возвращаем его.
    if (_aggregateStepsOverride.containsKey(date)) {
      final v = _aggregateStepsOverride[date]!;
      return v > 0 ? v : null;
    }

    // Авто-расчёт: суммируем все внешние записи шагов за день.
    // ⚠️ В реальном Health Connect aggregate() резолвит приоритет источников
    // и не суммирует. Это поведение проверяется пользователем на устройстве
    // (см. techContext.md). Для юнит-тестов резолюции override предпочтительнее.
    final externalPoints = _points.where(
      (p) =>
          p.type == HealthDataType.STEPS &&
          p.sourceId != appPackageId &&
          DateKey(p.dateFrom) == date,
    );

    if (externalPoints.isEmpty) return null;

    int total = 0;
    for (final p in externalPoints) {
      if (p.value is NumericHealthValue) {
        total += (p.value as NumericHealthValue).numericValue.toInt();
      }
    }
    return total > 0 ? total : null;
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  HealthDataType _toHealthDataType(MetricType type) => switch (type) {
    MetricType.weight => HealthDataType.WEIGHT,
    MetricType.steps => HealthDataType.STEPS,
  };

  HealthDataPoint _makePoint(DateTime date, HealthDataType type, num value, String sourceId) {
    return switch (type) {
      HealthDataType.WEIGHT => _makeWeightPoint(date, value.toDouble(), sourceId),
      HealthDataType.STEPS => _makeStepsPoint(date, value.toInt(), sourceId),
      _ => throw ArgumentError('Unsupported type for mock: $type'),
    };
  }

  HealthDataPoint _makeWeightPoint(DateTime date, double weight, String sourceId) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));
    return HealthDataPoint(
      sourceName: sourceId,
      uuid: '',
      sourceDeviceId: '',
      sourceId: sourceId,
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      value: NumericHealthValue(numericValue: weight),
      dateFrom: dayStart,
      dateTo: dayEnd,
      type: HealthDataType.WEIGHT,
      unit: HealthDataUnit.KILOGRAM,
    );
  }

  HealthDataPoint _makeStepsPoint(DateTime date, int steps, String sourceId) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));
    return HealthDataPoint(
      sourceName: sourceId,
      uuid: '',
      sourceDeviceId: '',
      sourceId: sourceId,
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      value: NumericHealthValue(numericValue: steps),
      dateFrom: dayStart,
      dateTo: dayEnd,
      type: HealthDataType.STEPS,
      unit: HealthDataUnit.COUNT,
    );
  }
}