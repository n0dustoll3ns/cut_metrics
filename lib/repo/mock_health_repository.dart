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
/// Ключевое: генерирует записи с разным `sourceId` (пакет приложения / внешние)
/// и разным `recordingMethod` (manual / automatic), что необходимо для
/// тестирования резолюции приоритета источников (Фаза 2, секция 5).
class MockHealthRepository implements HealthRepository {
  /// Идентификатор пакета приложения — определяет Tier 1.
  final String appPackageId;

  /// Счётчики вызовов методов (для тестов Фазы 4, DoD 3).
  int fetchRawDataCallCount = 0;
  int aggregateExternalStepsCallCount = 0;
  int aggregateExternalStepsForRangeCallCount = 0;

  /// Внутреннее хранилище всех точек данных.
  final List<HealthDataPoint> _points = [];

  /// Доступ только для чтения к внутреннему хранилищу (для тестов).
  List<HealthDataPoint> get points => List.unmodifiable(_points);

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
    addPoint(
      _makeWeightPoint(date, weight, sourceId ?? kExternalSourceId, RecordingMethod.automatic),
    );
  }

  /// Добавляет ручную запись веса (Tier 1).
  void addManualWeight(DateTime date, double weight) {
    addPoint(_makeWeightPoint(date, weight, appPackageId, RecordingMethod.manual));
  }

  /// Добавляет внешнюю запись шагов (Tier 2).
  void addExternalSteps(DateTime date, int steps, {String? sourceId}) {
    addPoint(
      _makeStepsPoint(date, steps, sourceId ?? kExternalSourceId, RecordingMethod.automatic),
    );
  }

  /// Добавляет ручную запись шагов (Tier 1).
  void addManualSteps(DateTime date, int steps) {
    addPoint(_makeStepsPoint(date, steps, appPackageId, RecordingMethod.manual));
  }

  /// Добавляет интервал стадии сна (DEEP/LIGHT/REM) — внешний трекер.
  ///
  /// [from]/[to] — точные временные метки (не день): интервалы сна пересекают
  /// полночь, анализатор группирует их по правилу «после 12:00 → следующий день».
  void addSleepStage(
    DateTime from,
    DateTime to, {
    HealthDataType type = HealthDataType.SLEEP_LIGHT,
    String sourceId = kExternalSourceId,
  }) {
    assert(
      type == HealthDataType.SLEEP_DEEP ||
          type == HealthDataType.SLEEP_LIGHT ||
          type == HealthDataType.SLEEP_REM,
      'addSleepStage expects a sleep stage type, got $type',
    );
    addPoint(_makeIntervalPoint(from, to, type, sourceId));
  }

  /// Добавляет интервал общей длительности сна (`SLEEP_ASLEEP`) — внешний трекер.
  void addSleepAsleep(
    DateTime from,
    DateTime to, {
    String sourceId = kExternalSourceId,
  }) {
    addPoint(_makeIntervalPoint(from, to, HealthDataType.SLEEP_ASLEEP, sourceId));
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
    fetchRawDataCallCount++;
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
    aggregateExternalStepsCallCount++;
    return _resolveAggregatedSteps(date);
  }

  @override
  Future<Map<DateKey, int>> aggregateExternalStepsForRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    aggregateExternalStepsForRangeCallCount++;
    final result = <DateKey, int>{};

    // Итерируем по дням, используя общую логику резолюции (_resolveAggregatedSteps)
    // напрямую, а не через aggregateExternalSteps — чтобы не увеличивать
    // счётчик подневных вызовов. В реальном репозитории это один батчевый запрос.
    final start = DateKey(startDate);
    final end = DateKey(endDate);
    final dayCount = end.value.difference(start.value).inDays;

    for (var d = 0; d <= dayCount; d++) {
      final date = DateKey(start.value.add(Duration(days: d)));
      final agg = await _resolveAggregatedSteps(date);
      if (agg != null && agg > 0) result[date] = agg;
    }

    return result;
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  /// Общая логика резолюции агрегированных внешних шагов для даты.
  ///
  /// 1. Если тест задал override для даты — возвращает его (или null если <= 0).
  /// 2. Иначе — авто-расчёт: суммирование внешних записей шагов за день.
  ///
  /// ⚠️ В реальном Health Connect `aggregate()` резолвит приоритет источников
  /// и не суммирует. Для тестов предпочтительнее `setAggregateExternalSteps`.
  /// Этот метод не инкрементит счётчики вызовов — это ответственность
  /// публичных методов [aggregateExternalSteps] / [aggregateExternalStepsForRange].
  Future<int?> _resolveAggregatedSteps(DateKey date) async {
    if (_aggregateStepsOverride.containsKey(date)) {
      final v = _aggregateStepsOverride[date]!;
      return v > 0 ? v : null;
    }

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

  HealthDataType _toHealthDataType(MetricType type) => switch (type) {
    MetricType.weight => HealthDataType.WEIGHT,
    MetricType.steps => HealthDataType.STEPS,
  };

  HealthDataPoint _makePoint(
    DateTime date,
    HealthDataType type,
    num value,
    String sourceId, {
    RecordingMethod recordingMethod = RecordingMethod.manual,
  }) {
    return switch (type) {
      HealthDataType.WEIGHT =>
        _makeWeightPoint(date, value.toDouble(), sourceId, recordingMethod),
      HealthDataType.STEPS => _makeStepsPoint(date, value.toInt(), sourceId, recordingMethod),
      _ => throw ArgumentError('Unsupported type for mock: $type'),
    };
  }

  HealthDataPoint _makeWeightPoint(
    DateTime date,
    double weight,
    String sourceId,
    RecordingMethod recordingMethod,
  ) {
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
      recordingMethod: recordingMethod,
    );
  }

  HealthDataPoint _makeIntervalPoint(
    DateTime from,
    DateTime to,
    HealthDataType type,
    String sourceId,
  ) {
    return HealthDataPoint(
      sourceName: sourceId,
      uuid: '',
      sourceDeviceId: '',
      sourceId: sourceId,
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      value: NumericHealthValue(numericValue: to.difference(from).inMinutes),
      dateFrom: from,
      dateTo: to,
      type: type,
      unit: HealthDataUnit.MINUTE,
      recordingMethod: RecordingMethod.automatic,
    );
  }

  HealthDataPoint _makeStepsPoint(
    DateTime date,
    int steps,
    String sourceId,
    RecordingMethod recordingMethod,
  ) {
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
      recordingMethod: recordingMethod,
    );
  }
}