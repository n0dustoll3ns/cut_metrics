import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/repo/health_repository.dart';
import 'package:health/health.dart';

/// Идентификатор пакета приложения — определяет Tier 1 записи.
const kAppPackageId = 'com.example.cut_metrics';

/// Внешний источник по умолчанию для мока (Google Fit).
const kExternalSourceId = 'com.google.android.apps.fitness';

/// Mock-реализация [HealthRepository] для юнит-тестов.
///
/// В отличие от реального репозитория, хранит данные в памяти и позволяет
/// тестам напрямую управлять содержимым через методы `add*`.
///
/// Ключевое: генерирует записи с разным пакетом источника (пакет приложения /
/// внешние приложения) и разным `recordingMethod` (manual / automatic), что
/// необходимо для тестирования резолюции приоритета источников.
///
/// Фаза 6: точки создаются как на реальном Android (A0-лог) — `sourceId`
/// пустой, пакет приложения приходит в `sourceName` (= `dataOrigin.packageName`).
/// Это заставляет тесты гонять реальный путь определения источника
/// (`HealthDataProcessor.sourcePackageOf`).
class MockHealthRepository implements HealthRepository {
  /// Идентификатор пакета приложения — определяет Tier 1.
  final String appPackageId;

  /// Счётчик вызовов `fetchRawData` (для тестов Фазы 4, DoD 3).
  int fetchRawDataCallCount = 0;

  /// Внутреннее хранилище всех точек данных.
  final List<HealthDataPoint> _points = [];

  /// Доступ только для чтения к внутреннему хранилищу (для тестов).
  List<HealthDataPoint> get points => List.unmodifiable(_points);

  MockHealthRepository({this.appPackageId = kAppPackageId});

  // ─── Управление данными для тестов ──────────────────────────────────────────

  /// Добавляет точку напрямую (низкоуровневый API для тестов).
  void addPoint(HealthDataPoint point) => _points.add(point);

  /// Добавляет внешнюю запись веса (Tier 2).
  void addExternalWeight(DateTime date, double weight, {String? sourcePackage}) {
    addPoint(
      _makeWeightPoint(date, weight, sourcePackage ?? kExternalSourceId, RecordingMethod.automatic),
    );
  }

  /// Добавляет ручную запись веса (Tier 1).
  void addManualWeight(DateTime date, double weight) {
    addPoint(_makeWeightPoint(date, weight, appPackageId, RecordingMethod.manual));
  }

  /// Добавляет внешнюю запись шагов (Tier 2).
  void addExternalSteps(DateTime date, int steps, {String? sourcePackage}) {
    addPoint(
      _makeStepsPoint(date, steps, sourcePackage ?? kExternalSourceId, RecordingMethod.automatic),
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
    String sourcePackage = kExternalSourceId,
  }) {
    assert(
      type == HealthDataType.SLEEP_DEEP ||
          type == HealthDataType.SLEEP_LIGHT ||
          type == HealthDataType.SLEEP_REM,
      'addSleepStage expects a sleep stage type, got $type',
    );
    addPoint(_makeIntervalPoint(from, to, type, sourcePackage));
  }

  /// Добавляет интервал общей длительности сна (`SLEEP_ASLEEP`) — внешний трекер.
  void addSleepAsleep(
    DateTime from,
    DateTime to, {
    String sourcePackage = kExternalSourceId,
  }) {
    addPoint(_makeIntervalPoint(from, to, HealthDataType.SLEEP_ASLEEP, sourcePackage));
  }

  /// Очищает все данные (для изоляции тестов).
  void clear() {
    _points.clear();
  }

  // ─── Реализация HealthRepository ────────────────────────────────────────────

  /// Наша ли точка (Tier 1) — по пакету источника, как на Android (A0).
  bool _isOurPoint(HealthDataPoint p) =>
      HealthDataProcessor.sourcePackageOf(p) == appPackageId;

  @override
  Future<bool> hasManualRecord(DateKey date, MetricType type) async {
    final healthType = _toHealthDataType(type);
    return _points.any(
      (p) => _isOurPoint(p) && p.type == healthType && DateKey(p.dateFrom) == date,
    );
  }

  @override
  Future<void> writeManualRecord(DateKey date, MetricType type, num value) async {
    final healthType = _toHealthDataType(type);
    // Delete-then-write (идемпотентность, A1.1) — как в реальном репозитории.
    _points.removeWhere(
      (p) => _isOurPoint(p) && p.type == healthType && DateKey(p.dateFrom) == date,
    );
    final point = _makePoint(date.value, healthType, value, appPackageId);
    _points.add(point);
  }

  @override
  Future<void> deleteManualRecord(DateKey date, MetricType type) async {
    final healthType = _toHealthDataType(type);
    _points.removeWhere(
      (p) => _isOurPoint(p) && p.type == healthType && DateKey(p.dateFrom) == date,
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

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  HealthDataType _toHealthDataType(MetricType type) => switch (type) {
    MetricType.weight => HealthDataType.WEIGHT,
    MetricType.steps => HealthDataType.STEPS,
  };

  HealthDataPoint _makePoint(
    DateTime date,
    HealthDataType type,
    num value,
    String sourcePackage, {
    RecordingMethod recordingMethod = RecordingMethod.manual,
  }) {
    return switch (type) {
      HealthDataType.WEIGHT =>
        _makeWeightPoint(date, value.toDouble(), sourcePackage, recordingMethod),
      HealthDataType.STEPS => _makeStepsPoint(date, value.toInt(), sourcePackage, recordingMethod),
      _ => throw ArgumentError('Unsupported type for mock: $type'),
    };
  }

  /// Точка «как на реальном Android» (A0-лог): `sourceId` пустой, пакет
  /// приложения-источника приходит в `sourceName`.
  HealthDataPoint _makeWeightPoint(
    DateTime date,
    double weight,
    String sourcePackage,
    RecordingMethod recordingMethod,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));
    return HealthDataPoint(
      sourceName: sourcePackage,
      uuid: '',
      sourceDeviceId: '',
      sourceId: '',
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
    String sourcePackage,
  ) {
    return HealthDataPoint(
      sourceName: sourcePackage,
      uuid: '',
      sourceDeviceId: '',
      sourceId: '',
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
    String sourcePackage,
    RecordingMethod recordingMethod,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));
    return HealthDataPoint(
      sourceName: sourcePackage,
      uuid: '',
      sourceDeviceId: '',
      sourceId: '',
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