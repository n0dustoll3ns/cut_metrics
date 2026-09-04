import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
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
/// Фаза 2: чтение и запись в Health Connect. Фаза 6: шаги — только сырые точки
/// (aggregate-методы удалены), запись идемпотентна (delete-then-write), наш
/// пакет распознаётся по `sourceName` (A0: `sourceId` на Android пуст).
///
/// **Tier 1** (ручной ввод):
/// - [writeManualRecord] — delete-then-write + `writeHealthData` с
///   `RecordingMethod.manual`.
/// - [hasManualRecord] — читает точки и фильтрует по
///   `HealthDataProcessor.sourcePackageOf(p) == appPackageId`.
/// - [deleteManualRecord] — удаляет через `delete`.
///
/// **Tier 2** (внешние источники):
/// - [fetchRawData] — `getHealthDataFromTypes` для всех метрик; резолюция
///   шагов по сырым точкам — в `HealthDataProcessor` («один источник на день»).
///
/// ⚠️ Техриск №3 (см. `techContext.md`): `delete()` ограничен записями своего
/// приложения — проверить на устройстве при UX «отменить правку».
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
    // Фаза 6, A0: наш пакет распознаётся по sourceName (sourceId на Android
    // всегда пустой — баг пакета health 13.3.1/13.3.2).
    final has = points.any((p) => HealthDataProcessor.sourcePackageOf(p) == appPackageId);
    DebugLog.instance.log(
      'repo',
      'hasManualRecord $date ${_toHealthDataType(type).name}: '
      '${points.length} точек, '
      'sourceName=[${points.map(HealthDataProcessor.sourcePackageOf).toSet().join(', ')}], '
      'наш пакет=$appPackageId → $has',
    );
    return has;
  }

  @override
  Future<void> writeManualRecord(DateKey date, MetricType type, num value) async {
    final healthType = _toHealthDataType(type);
    final isSteps = type == MetricType.steps;

    // Идемпотентность (Фаза 6, A1.1): сначала удаляем наши записи за дату,
    // иначе повторный submit дописывает новую запись и плодит дубли.
    // `delete` платформенно ограничен записями нашего приложения, внешние
    // данные за эту дату не затрагиваются; false — как правило «своих записей
    // нет», это не ошибка (log warn, не throw).
    final deleted = await health.delete(
      type: healthType,
      startTime: date.startOfDay,
      endTime: date.endOfDay,
    );
    if (!deleted) {
      DebugLog.instance.warn(
        'repo',
        'writeManualRecord $date ${healthType.name}: delete-then-write — '
        'delete вернул false (своих записей на дату, вероятно, нет)',
      );
    }

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
      final sources = points.map(HealthDataProcessor.sourcePackageOf).toSet().join(', ');
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