import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/repo/health_repository.dart';
import 'package:cut_metrics/services/debug_log.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';

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
    final has = points.any((p) => p.sourceId == appPackageId);
    // Техриск №1 (techContext.md): видно реальные sourceId за дату и совпадение
    // с package name нашего приложения.
    DebugLog.instance.log(
      'repo',
      'hasManualRecord $date ${_toHealthDataType(type).name}: '
      '${points.length} точек, '
      'sourceId=[${points.map((p) => p.sourceId).toSet().join(', ')}], '
      'наш пакет=$appPackageId → $has',
    );
    return has;
  }

  @override
  Future<void> writeManualRecord(DateKey date, MetricType type, num value) async {
    final healthType = _toHealthDataType(type);
    final isSteps = type == MetricType.steps;

    DebugLog.instance.log(
      'repo',
      'writeManualRecord $date ${healthType.name} = $value (manual)…',
    );
    final success = await health.writeHealthData(
      value: value.toDouble(),
      type: healthType,
      startTime: date.startOfDay,
      endTime: isSteps ? date.endOfDay : date.startOfDay,
      recordingMethod: RecordingMethod.manual,
    );

    if (!success) {
      DebugLog.instance.error(
        'repo',
        'writeManualRecord $date ${healthType.name} = $value: '
        'writeHealthData вернул false',
      );
      throw const HealthRepositoryException(
        'Не удалось записать значение в Health Connect (writeHealthData вернул false)',
      );
    }
    DebugLog.instance.log(
      'repo',
      'writeManualRecord $date ${healthType.name} = $value: OK',
    );
  }

  @override
  Future<void> deleteManualRecord(DateKey date, MetricType type) async {
    final healthType = _toHealthDataType(type);
    DebugLog.instance.log(
      'repo',
      'deleteManualRecord $date ${healthType.name}…',
    );

    final success = await health.delete(
      type: healthType,
      startTime: date.startOfDay,
      endTime: date.endOfDay,
    );

    if (!success) {
      // Техриск №3: delete платформенно ограничен записями своего приложения —
      // false может означать и «нет своих записей», и платформенное ограничение.
      DebugLog.instance.error(
        'repo',
        'deleteManualRecord $date ${healthType.name}: delete вернул false '
        '(нет своих записей на дату или платформенное ограничение?)',
      );
      throw const HealthRepositoryException(
        'Не удалось удалить запись из Health Connect (delete вернул false)',
      );
    }
    DebugLog.instance.log(
      'repo',
      'deleteManualRecord $date ${healthType.name}: OK',
    );
  }

  // ─── Tier 2: внешние источники ──────────────────────────────────────────────

  @override
  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final names = _typeNames(types);
    DebugLog.instance.log(
      'repo',
      'fetchRawData $names ${_fmt(startDate)} → ${_fmt(endDate)}…',
    );
    try {
      final points = await health.getHealthDataFromTypes(
        startTime: startDate,
        endTime: endDate,
        types: types,
      );
      final sources = points.map((p) => p.sourceId).toSet().join(', ');
      DebugLog.instance.log(
        'repo',
        'fetchRawData $names: ${points.length} точек, '
        'источники: ${sources.isEmpty ? '—' : sources}',
      );
      return points;
    } catch (e) {
      DebugLog.instance.error('repo', 'fetchRawData $names: исключение $e');
      rethrow;
    }
  }

  @override
  Future<int?> aggregateExternalSteps(DateKey date) async {
    final result =
        await health.getTotalStepsInInterval(date.startOfDay, date.endOfDay);
    // Техриск №2: getTotalStepsInInterval должен использовать нативный
    // aggregate() с приоритетом источников, а не сумму сырых записей.
    DebugLog.instance.log(
      'repo',
      'aggregateExternalSteps $date (getTotalStepsInInterval) → $result',
    );
    return result;
  }

  @override
  Future<Map<DateKey, int>> aggregateExternalStepsForRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    // Один запрос к Health Connect на весь диапазон с бакетами по дням
    // (interval = 1440 минут = 1 сутки). Фаза 4, DoD 3 — не более 1–2 вызовов
    // на метрику при загрузке диапазона.
    //
    // ⚠️ Техриск №4 (см. techContext.md): неизвестно, использует ли
    // getHealthIntervalDataFromTypes тот же нативный aggregate() с приоритетом
    // источников, что и getTotalStepsInInterval, или суммирует сырые записи.
    // Результат по дням виден в DebugLog — там должно быть одно значение
    // на день, а не сумма нескольких источников.
    DebugLog.instance.log(
      'repo',
      'aggregateExternalStepsForRange ${_fmt(startDate)} → ${_fmt(endDate)} '
      '(getHealthIntervalDataFromTypes, interval=1440)…',
    );
    try {
      final points = await health.getHealthIntervalDataFromTypes(
        startDate: startDate,
        endDate: endDate,
        types: const [HealthDataType.STEPS],
        interval: 1440,
      );

      final result = <DateKey, int>{};
      for (final p in points) {
        if (p.value is NumericHealthValue) {
          final steps = (p.value as NumericHealthValue).numericValue.toInt();
          if (steps > 0) {
            result[DateKey(p.dateFrom)] = steps;
          }
        }
      }
      final days = result.entries
          .map((e) => '${e.key.value.month}-${e.key.value.day}:${e.value}')
          .join(' ');
      DebugLog.instance.log(
        'repo',
        'aggregateExternalStepsForRange: ${result.length} дней с шагами'
        '${result.isEmpty ? '' : ': $days'}',
      );
      return result;
    } catch (e) {
      DebugLog.instance.error(
        'repo',
        'aggregateExternalStepsForRange: исключение $e',
      );
      rethrow;
    }
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  /// Имена типов для лога: до 3 типов — поимённо, больше — счётчиком
  /// (сон запрашивает 10 типов, строка была бы нечитаемой).
  static String _typeNames(List<HealthDataType> types) => types.length <= 3
      ? types.map((t) => t.name).join('+')
      : '${types.length} types';

  /// `yyyy-MM-dd HH:mm` для лога.
  static String _fmt(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d);

  HealthDataType _toHealthDataType(MetricType type) => switch (type) {
    MetricType.weight => HealthDataType.WEIGHT,
    MetricType.steps => HealthDataType.STEPS,
  };
}