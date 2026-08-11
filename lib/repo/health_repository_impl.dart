import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/repo/health_repository.dart';
import 'package:health/health.dart';

/// Типизированное исключение для ошибок репозитория.
///
/// Не глушит ошибки записи/удаления — пробрасывает наверх, чтобы ViewModel
/// мог показать пользователю фидбек (Фаза 2, секция 6).
class HealthRepositoryException implements Exception {
  final String message;
  final Object? cause;

  const HealthRepositoryException(this.message, {this.cause});

  @override
  String toString() => 'HealthRepositoryException: $message';
}

/// Реализация [HealthRepository] поверх пакета `health` (Health Connect).
///
/// Фаза 2: чтение и запись в Health Connect.
///
/// **Tier 1** (ручной ввод):
/// - [writeManualRecord] — пишет через `writeHealthData` с `RecordingMethod.manual`.
/// - [hasManualRecord] — читает точки и фильтрует по `sourceId == appPackageId`.
/// - [deleteManualRecord] — удаляет через `delete`.
///
/// **Tier 2** (внешние источники):
/// - [fetchRawData] — `getHealthDataFromTypes` (вес и др.).
/// - [aggregateExternalSteps] — `getTotalStepsInInterval` (нативный `aggregate()`).
///
/// ⚠️ Три технических риска, требующих проверки на устройстве (см. `techContext.md`):
/// 1. `sourceId` — равен ли package name приложения.
/// 2. `getTotalStepsInInterval` — использует ли нативный `aggregate()` с приоритетом источников.
/// 3. `delete()` — ограничен ли только записями своего приложения.
class HealthRepositoryImpl implements HealthRepository {
  final Health health;
  final String appPackageId;

  HealthRepositoryImpl({
    required this.health,
    required this.appPackageId,
  });

  // ─── Tier 1: ручной ввод ────────────────────────────────────────────────────

  @override
  Future<bool> hasManualRecord(DateKey date, MetricType type) async {
    final points = await health.getHealthDataFromTypes(
      startTime: date.startOfDay,
      endTime: date.endOfDay,
      types: [_toHealthDataType(type)],
    );
    return points.any((p) => p.sourceId == appPackageId);
  }

  @override
  Future<void> writeManualRecord(DateKey date, MetricType type, num value) async {
    final healthType = _toHealthDataType(type);
    final isSteps = type == MetricType.steps;

    final success = await health.writeHealthData(
      value: value.toDouble(),
      type: healthType,
      startTime: date.startOfDay,
      endTime: isSteps ? date.endOfDay : date.startOfDay,
      recordingMethod: RecordingMethod.manual,
    );

    if (!success) {
      throw const HealthRepositoryException(
        'Не удалось записать значение в Health Connect (writeHealthData вернул false)',
      );
    }
  }

  @override
  Future<void> deleteManualRecord(DateKey date, MetricType type) async {
    final success = await health.delete(
      type: _toHealthDataType(type),
      startTime: date.startOfDay,
      endTime: date.endOfDay,
    );

    if (!success) {
      throw const HealthRepositoryException(
        'Не удалось удалить запись из Health Connect (delete вернул false)',
      );
    }
  }

  // ─── Tier 2: внешние источники ──────────────────────────────────────────────

  @override
  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return health.getHealthDataFromTypes(
      startTime: startDate,
      endTime: endDate,
      types: types,
    );
  }

  @override
  Future<int?> aggregateExternalSteps(DateKey date) {
    return health.getTotalStepsInInterval(date.startOfDay, date.endOfDay);
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  HealthDataType _toHealthDataType(MetricType type) => switch (type) {
    MetricType.weight => HealthDataType.WEIGHT,
    MetricType.steps => HealthDataType.STEPS,
  };
}