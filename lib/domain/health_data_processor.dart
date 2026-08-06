import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:health/health.dart';

/// Слой бизнес-логики: резолюция приоритета источников (Tier 1 → Tier 2).
///
/// **Чистая синхронная функция** — работает с предзагруженными данными,
/// не вызывает репозиторий. Это позволяет:
/// 1. Тестировать без моков репозитория — просто передаёшь массив точек.
/// 2. Не делать N запросов на N дат — данные грузятся батчем в ViewModel
///    (⚠️ критичное требование из `systemPatterns.md`).
///
/// **Tier 1** — запись с `sourceId` = [appPackageId] (ручной ввод).
/// Всегда побеждает, если существует на дату.
///
/// **Tier 2** — внешние записи (фолбэк).
/// - Вес: last-wins по времени записи.
/// - Шаги: значение из нативного `aggregate()` (передаётся извне как
///   `aggregatedExternal`, не суммируется в этом классе).
class HealthDataProcessor {
  /// Идентификатор пакета приложения — определяет Tier 1 записи.
  final String appPackageId;

  HealthDataProcessor({required this.appPackageId});

  // ─── Вес: резолюция на одну дату ────────────────────────────────────────────

  /// Резолюция веса для конкретной даты.
  ///
  /// 1. Есть точка с `sourceId` = [appPackageId]? → `WeightDay(source: manual)`.
  /// 2. Иначе — last-wins среди внешних точек → `WeightDay(source: external)`.
  /// 3. Нет данных → `null`.
  WeightDay? resolveWeightForDate(DateKey date, List<HealthDataPoint> weightPoints) {
    final dayPoints = weightPoints.where((p) => DateKey(p.dateFrom) == date).toList();
    if (dayPoints.isEmpty) return null;

    // Tier 1: ручная запись
    final manualPoints = dayPoints.where((p) => p.sourceId == appPackageId).toList();
    if (manualPoints.isNotEmpty) {
      final last = _lastByTime(manualPoints);
      return WeightDay(
        date: date,
        weight: _numericValue(last),
        source: DataSource.manual,
      );
    }

    // Tier 2: внешние, last-wins
    final last = _lastByTime(dayPoints);
    return WeightDay(
      date: date,
      weight: _numericValue(last),
      source: DataSource.external,
    );
  }

  // ─── Шаги: резолюция на одну дату ───────────────────────────────────────────

  /// Резолюция шагов для конкретной даты.
  ///
  /// 1. Есть точка с `sourceId` = [appPackageId]? → `StepsDay(source: manual)`.
  ///    Все внешние записи игнорируются.
  /// 2. Иначе — [aggregatedExternal] > 0? → `StepsDay(source: external)`.
  /// 3. Нет данных → `null`.
  ///
  /// [aggregatedExternal] — результат нативного Health Connect `aggregate()`,
  /// который учитывает приоритет источников из настроек ОС. Передаётся извне,
  /// потому что это асинхронный вызов репозитория, а процессор — чистая функция.
  StepsDay? resolveStepsForDate(
    DateKey date,
    List<HealthDataPoint> stepsPoints,
    int? aggregatedExternal,
  ) {
    final dayPoints = stepsPoints.where((p) => DateKey(p.dateFrom) == date).toList();

    // Tier 1: ручная запись
    final manualPoints = dayPoints.where((p) => p.sourceId == appPackageId).toList();
    if (manualPoints.isNotEmpty) {
      final last = _lastByTime(manualPoints);
      return StepsDay(
        date: date,
        steps: _numericValue(last).toInt(),
        source: DataSource.manual,
      );
    }

    // Tier 2: агрегированные внешние шаги
    if (aggregatedExternal != null && aggregatedExternal > 0) {
      return StepsDay(
        date: date,
        steps: aggregatedExternal,
        source: DataSource.external,
      );
    }

    return null;
  }

  // ─── Батчевая резолюция на диапазон ─────────────────────────────────────────
  //
  // ⚠️ Критично: резолюция должна работать батчево на весь диапазон дат,
  // а не отдельным запросом на каждый день (systemPatterns.md).
  // Методы ниже принимают предзагруженные данные и резолвят все даты in-memory.

  /// Резолюция веса для всех дат в предзагруженном списке точек.
  ///
  /// Возвращает Map с резолютированными значениями для каждой даты, где есть
  /// хотя бы одна запись.
  Map<DateKey, WeightDay> resolveWeightForAllDates(List<HealthDataPoint> weightPoints) {
    final result = <DateKey, WeightDay>{};

    // Группируем по дате
    final byDate = <DateKey, List<HealthDataPoint>>{};
    for (final p in weightPoints) {
      byDate.putIfAbsent(DateKey(p.dateFrom), () => []).add(p);
    }

    for (final entry in byDate.entries) {
      final resolved = resolveWeightForDate(entry.key, weightPoints);
      if (resolved != null) result[entry.key] = resolved;
    }

    return result;
  }

  /// Резолюция шагов для всех дат.
  ///
  /// [aggregatedExternalByDate] — Map с результатами нативного `aggregate()`
  /// для каждой даты (полученными из репозитория заранее).
  Map<DateKey, StepsDay> resolveStepsForAllDates(
    List<HealthDataPoint> stepsPoints,
    Map<DateKey, int> aggregatedExternalByDate,
  ) {
    final result = <DateKey, StepsDay>{};

    // Собираем все даты: из сырых точек + из агрегированных
    final allDates = <DateKey>{};
    for (final p in stepsPoints) {
      allDates.add(DateKey(p.dateFrom));
    }
    allDates.addAll(aggregatedExternalByDate.keys);

    for (final date in allDates) {
      final aggregated = aggregatedExternalByDate[date];
      final resolved = resolveStepsForDate(date, stepsPoints, aggregated);
      if (resolved != null) result[date] = resolved;
    }

    return result;
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  /// Возвращает точку с последним `dateFrom` (last-wins).
  HealthDataPoint _lastByTime(List<HealthDataPoint> points) {
    final sorted = [...points]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    return sorted.last;
  }

  /// Извлекает числовое значение из [NumericHealthValue].
  double _numericValue(HealthDataPoint point) {
    final v = point.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    throw StateError('Expected NumericHealthValue, got ${v.runtimeType}');
  }
}