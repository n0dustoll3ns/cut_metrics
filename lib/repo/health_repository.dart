import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:health/health.dart';

/// Контракт репозитория для доступа к Health Connect.
///
/// Фаза 1 фиксирует сигнатуры методов, от которых зависит резолюция источников.
/// Реализация — в Фазе 2 (`HealthRepositoryImpl`).
///
/// **Tier 1** (ручной ввод) — методы `hasManualRecord` / `writeManualRecord` /
/// `deleteManualRecord`. Записи с `sourceId` = пакет приложения всегда побеждают.
///
/// **Tier 2** (внешние источники):
/// - Вес — [fetchRawData] (last-wins по времени записи в процессоре).
/// - Шаги — [aggregateExternalSteps] (нативный `aggregate()`, не суммирование).
abstract class HealthRepository {
  /// Проверяет, есть ли ручная запись (Tier 1) для [date] и [type].
  Future<bool> hasManualRecord(DateKey date, MetricType type);

  /// Записывает ручное значение (Tier 1) в Health Connect.
  Future<void> writeManualRecord(DateKey date, MetricType type, num value);

  /// Удаляет ручную запись (Tier 1) для [date] и [type].
  ///
  /// После удаления при следующей резолюции алгоритм естественным образом
  /// откатывается на Tier 2 — отдельной логики отката не требуется.
  Future<void> deleteManualRecord(DateKey date, MetricType type);

  /// Чтение сырых точек данных из Health Connect.
  ///
  /// Используется для веса (Tier 2) и других метрик. Возвращает все записи
  /// в диапазоне `[startDate, endDate]` для указанных [types].
  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  });

  /// Агрегированные шаги за день через нативный Health Connect `aggregate()`.
  ///
  /// Заменяет `readRecords()` + суммирование для Tier 2. Нативный `aggregate()`
  /// учитывает приоритет источников из системных настроек, поэтому не происходит
  /// задвоения при нескольких внешних источниках.
  ///
  /// Возвращает `null` или `0`, если данных нет.
  Future<int?> aggregateExternalSteps(DateKey date);
}