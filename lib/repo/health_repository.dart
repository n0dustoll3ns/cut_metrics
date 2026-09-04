import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:health/health.dart';

/// Контракт репозитория для доступа к Health Connect.
///
/// Фаза 6, A2: aggregate-методы шагов (`aggregateExternalSteps`,
/// `aggregateExternalStepsForRange`) удалены — резолюция шагов идёт по сырым
/// точкам («один источник на день», `HealthDataProcessor`), техриски №2/№4
/// закрыты архитектурно. Батчевость сохранена: один `fetchRawData` на
/// диапазон для каждой метрики.
///
/// **Tier 1** (ручной ввод) — методы `hasManualRecord` / `writeManualRecord` /
/// `deleteManualRecord`. Записи с пакетом источника = пакет приложения всегда
/// побеждают (определение пакета — `HealthDataProcessor.sourcePackageOf`).
///
/// **Tier 2** (внешние источники) — [fetchRawData] для всех метрик: вес
/// (last-wins в процессоре), шаги («один источник на день» в процессоре).
abstract class HealthRepository {
  /// Проверяет, есть ли ручная запись (Tier 1) для [date] и [type].
  Future<bool> hasManualRecord(DateKey date, MetricType type);

  /// Записывает ручное значение (Tier 1) в Health Connect.
  ///
  /// Идемпотентен (Фаза 6, A1.1): перед записью удаляет наши записи за дату
  /// (delete-then-write), поэтому повторный submit не плодит дубли.
  Future<void> writeManualRecord(DateKey date, MetricType type, num value);

  /// Удаляет ручную запись (Tier 1) для [date] и [type].
  ///
  /// После удаления при следующей резолюции алгоритм естественным образом
  /// откатывается на Tier 2 — отдельной логики отката не требуется.
  Future<void> deleteManualRecord(DateKey date, MetricType type);

  /// Чтение сырых точек данных из Health Connect.
  ///
  /// Единый источник данных для всех метрик (вес, шаги, сон): возвращает все
  /// записи в диапазоне `[startDate, endDate]` для указанных [types].
  /// Один вызов на диапазон на метрику (Фаза 4, DoD 3).
  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  });
}
