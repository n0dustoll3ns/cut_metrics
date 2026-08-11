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
  ///
  /// Используется в [_reloadDate] для обновления одной даты после submit/cancel.
  Future<int?> aggregateExternalSteps(DateKey date);

  /// Агрегированные шаги за диапазон дат одним запросом (Фаза 4, DoD 3).
  ///
  /// Батчевый аналог [aggregateExternalSteps] — один вызов к Health Connect
  /// на весь диапазон вместо N вызовов по одному на каждый день. Используется
  /// при [DashboardViewModel.load] для холодного старта.
  ///
  /// Возвращает Map с агрегированными значениями для каждой даты, где есть
  /// ненулевой результат.
  Future<Map<DateKey, int>> aggregateExternalStepsForRange(
    DateTime startDate,
    DateTime endDate,
  );
}
