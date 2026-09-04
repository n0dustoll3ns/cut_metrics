import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:health/health.dart';

/// Слой бизнес-логики: резолюция приоритета источников (Tier 1 → Tier 2).
///
/// **Чистые синхронные функции** — работают с предзагруженными данными,
/// не вызывают репозиторий. Это позволяет:
/// 1. Тестировать без моков репозитория — просто передаёшь массив точек.
/// 2. Не делать N запросов на N дат — данные грузятся батчем в ViewModel
///    (⚠️ критичное требование из `systemPatterns.md`).
///
/// **Пакет источника (Фаза 6, A0):** на Android у пакета `health` 13.3.1/13.3.2
/// `sourceId` ВСЕГДА пустой (`HealthDataConverter.createBaseRecord` отдаёт
/// захардкоженный `""`), реальный пакет приложения приходит в `sourceName` =
/// `metadata.dataOrigin.packageName`. Поэтому [sourcePackageOf] берёт
/// `sourceName`, а `sourceId` — только fallback (iOS/будущие версии).
///
/// **Tier 1** (ручной ввод) — точка с `sourcePackage` = [appPackageId].
/// Всегда побеждает, если существует на дату.
///
/// **Tier 2** (Фаза 6, C.2):
/// 1. Отбрасываются источники с решением `refused` ([ConfirmDecision.refused]).
/// 2. Выбрано приложение ([SourceSelection.app]) — только его точки.
/// 3. «Авто»: вес — last-wins по `dateFrom`; шаги — «один источник на день»:
///    источник с максимальной суммой за день, значение = сумма его точек
///    (замена нативного `aggregate()`, техриски №2/№4 закрыты архитектурно).
/// 4. Пригодных точек нет → `null`.
class HealthDataProcessor {
  /// Идентификатор пакета приложения — определяет Tier 1 записи.
  final String appPackageId;

  HealthDataProcessor({required this.appPackageId});

  // ─── Пакет источника точки ─────────────────────────────────────────────────

  /// Пакет приложения-источника точки: `sourceName` (Android — реальный
  /// `dataOrigin.packageName`), fallback — `sourceId` (iOS/будущие версии).
  ///
  /// Один источник истины для Tier 1, списка источников и `sourcePackage`
  /// в результатах — не сравнивать `sourceId` напрямую (он пуст на Android).
  static String sourcePackageOf(HealthDataPoint point) {
    final name = point.sourceName;
    if (name.isNotEmpty) return name;
    return point.sourceId;
  }

  /// Наша ли это точка (Tier 1 — ручной ввод через Cut Metrics)?
  bool isOurPoint(HealthDataPoint point) =>
      sourcePackageOf(point) == appPackageId;

  // ─── Вес: резолюция на одну дату ────────────────────────────────────────────

  /// Резолюция веса для конкретной даты.
  ///
  /// 1. Есть наша точка (Tier 1)? → `WeightDay(source: manual)` — последняя
  ///    по времени.
  /// 2. Иначе Tier 2: refused-фильтр → выбранный источник («Авто» — last-wins).
  /// 3. Нет пригодных данных → `null`.
  ///
  /// [decisions] — карта пакет → решение пользователя (B.1),
  /// [selection] — выбранный источник для метрики (C.1).
  WeightDay? resolveWeightForDate(
    DateKey date,
    List<HealthDataPoint> weightPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
  }) {
    final dayPoints = weightPoints
        .where((p) => DateKey(p.dateFrom) == date)
        .toList();
    if (dayPoints.isEmpty) return null;

    // Tier 1: ручная запись — всегда побеждает.
    final ourPoints = dayPoints.where(isOurPoint).toList();
    if (ourPoints.isNotEmpty) {
      final last = _lastByTime(ourPoints);
      return WeightDay(
        date: date,
        weight: _numericValue(last),
        source: DataSource.manual,
        sourcePackage: appPackageId,
      );
    }

    // Tier 2: refused-фильтр + выбор источника, last-wins.
    final pool = _tier2Pool(dayPoints, decisions, selection);
    if (pool.isEmpty) return null;
    final last = _lastByTime(pool);
    return WeightDay(
      date: date,
      weight: _numericValue(last),
      source: DataSource.external,
      sourcePackage: sourcePackageOf(last),
    );
  }

  // ─── Шаги: резолюция на одну дату ───────────────────────────────────────────

  /// Резолюция шагов для конкретной даты — по сырым точкам (Фаза 6, A2).
  ///
  /// 1. Есть наша точка (Tier 1)? → `StepsDay(source: manual)` — последняя по
  ///    времени (после идемпотентной записи delete-then-write она одна).
  /// 2. Иначе Tier 2, правило «один источник на день»:
  ///    - выбран источник ([SourceSelection.app]) — сумма его точек за день;
  ///    - «Авто» — источник с максимальной суммой за день среди неотклонённых;
  ///      если в дне несколько источников, вызывается [onWarn] (диагностика
  ///      выбора — логируется вызывающей стороной, процессор остаётся чистым).
  /// 3. Нет пригодных данных → `null`.
  StepsDay? resolveStepsForDate(
    DateKey date,
    List<HealthDataPoint> stepsPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
    void Function(String message)? onWarn,
  }) {
    final dayPoints = stepsPoints
        .where((p) => DateKey(p.dateFrom) == date)
        .toList();
    if (dayPoints.isEmpty) return null;

    // Tier 1: ручная запись — всегда побеждает.
    final ourPoints = dayPoints.where(isOurPoint).toList();
    if (ourPoints.isNotEmpty) {
      final last = _lastByTime(ourPoints);
      return StepsDay(
        date: date,
        steps: _numericValue(last).toInt(),
        source: DataSource.manual,
        sourcePackage: appPackageId,
      );
    }

    final pool = _tier2Pool(dayPoints, decisions, selection);
    if (pool.isEmpty) return null;

    if (selection.isAuto) {
      // «Авто»: группируем по источникам, берём максимальную сумму за день.
      final bySource = <String, List<HealthDataPoint>>{};
      for (final p in pool) {
        bySource.putIfAbsent(sourcePackageOf(p), () => []).add(p);
      }
      if (bySource.length > 1) {
        onWarn?.call(
          'шаги $date: несколько источников (${bySource.keys.join(', ')}) — '
          'взят источник с максимальной суммой за день',
        );
      }
      var bestSource = bySource.keys.first;
      var bestSum = -1;
      for (final entry in bySource.entries) {
        final sum = entry.value.fold<int>(
          0,
          (acc, p) => acc + _numericValue(p).toInt(),
        );
        if (sum > bestSum) {
          bestSum = sum;
          bestSource = entry.key;
        }
      }
      if (bestSum <= 0) return null;
      return StepsDay(
        date: date,
        steps: bestSum,
        source: DataSource.external,
        sourcePackage: bestSource,
      );
    }

    // Выбран конкретный источник: сумма его точек за день.
    final sum = pool.fold<int>(
      0,
      (acc, p) => acc + _numericValue(p).toInt(),
    );
    if (sum <= 0) return null;
    return StepsDay(
      date: date,
      steps: sum,
      source: DataSource.external,
      sourcePackage: selection.package,
    );
  }

  // ─── Батчевая резолюция на диапазон ─────────────────────────────────────────
  //
  // ⚠️ Критично: резолюция должна работать батчево на весь диапазон дат,
  // а не отдельным запросом на каждый день (systemPatterns.md).
  // Методы ниже принимают предзагруженные данные и резолвят все даты in-memory.

  /// Резолюция веса для всех дат в предзагруженном списке точек.
  ///
  /// Возвращает Map с резолютированными значениями для каждой даты, где есть
  /// хотя бы одна пригодная запись.
  Map<DateKey, WeightDay> resolveWeightForAllDates(
    List<HealthDataPoint> weightPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
  }) {
    final result = <DateKey, WeightDay>{};

    // Группируем по дате
    final byDate = <DateKey, List<HealthDataPoint>>{};
    for (final p in weightPoints) {
      byDate.putIfAbsent(DateKey(p.dateFrom), () => []).add(p);
    }

    for (final entry in byDate.entries) {
      final resolved = resolveWeightForDate(
        entry.key,
        weightPoints,
        decisions: decisions,
        selection: selection,
      );
      if (resolved != null) result[entry.key] = resolved;
    }

    return result;
  }

  /// Резолюция шагов для всех дат — только по сырым точкам (A2: aggregate-API
  /// удалены из архитектуры, один `fetchRawData` на диапазон — Фаза 4, DoD 3).
  Map<DateKey, StepsDay> resolveStepsForAllDates(
    List<HealthDataPoint> stepsPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
    void Function(String message)? onWarn,
  }) {
    final result = <DateKey, StepsDay>{};

    final byDate = <DateKey, List<HealthDataPoint>>{};
    for (final p in stepsPoints) {
      byDate.putIfAbsent(DateKey(p.dateFrom), () => []).add(p);
    }

    for (final entry in byDate.entries) {
      final resolved = resolveStepsForDate(
        entry.key,
        stepsPoints,
        decisions: decisions,
        selection: selection,
        onWarn: onWarn,
      );
      if (resolved != null) result[entry.key] = resolved;
    }

    return result;
  }

  // ─── Список найденных источников (C.1) ──────────────────────────────────────

  /// Уникальные пакеты внешних источников (наш пакет не входит — Tier 1
  /// всегда побеждает). Строится по сырым точкам сессии, без дополнительных
  /// запросов к Health Connect.
  List<String> externalSources(List<HealthDataPoint> points) {
    final sources = points
        .map(sourcePackageOf)
        .where((s) => s != appPackageId)
        .toSet();
    return sources.toList()..sort();
  }

  // ─── EMA (экспоненциальное сглаживание) ──────────────────────────────────────

  /// Пересчитывает EMA по всему кешу весов и возвращает новый кеш EMA.
  ///
  /// Алгоритм: стандартная EMA с множителем `2 / (period + 1)`.
  /// Первая точка инициализируется самим значением веса, далее каждая
  /// следующая точка: `ema = (weight - prevEma) * multiplier + prevEma`.
  ///
  /// Период [period] определяет сглаживание: больше период — сильнее сглаживание.
  /// EMA-точки не имеют отношения к приоритету источников, поэтому `source`
  /// устанавливается в [DataSource.external] (значение не используется
  /// потребителем), `sourcePackage` — `null`.
  ///
  /// ⚠️ Полный пересчёт при каждом вызове — известный TODO по производительности
  /// при данных за год+, принимается как есть (см. `systemPatterns.md`).
  Map<DateKey, WeightDay> computeEma(Map<DateKey, WeightDay> weightCache, int period) {
    if (weightCache.isEmpty) return {};

    final sorted = weightCache.values.toList()..sort((a, b) => a.date.compareTo(b.date));

    final multiplier = 2 / (period + 1);
    double ema = sorted.first.weight;

    final result = <WeightDay>[
      WeightDay(date: sorted.first.date, weight: ema, source: DataSource.external),
    ];
    for (int i = 1; i < sorted.length; i++) {
      ema = (sorted[i].weight - ema) * multiplier + ema;
      result.add(WeightDay(date: sorted[i].date, weight: ema, source: DataSource.external));
    }

    return Map.fromEntries(result.map((e) => MapEntry(e.date, e)));
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  /// Tier 2-пул точек дня: не наши, не отклонённые, при выбранном источнике —
  /// только его точки (C.2, шаги 1–2).
  List<HealthDataPoint> _tier2Pool(
    List<HealthDataPoint> dayPoints,
    Map<String, ConfirmDecision> decisions,
    SourceSelection selection,
  ) {
    final notRefused = dayPoints.where((p) {
      if (isOurPoint(p)) return false;
      return decisions[sourcePackageOf(p)] != ConfirmDecision.refused;
    });
    if (!selection.isAuto) {
      return notRefused
          .where((p) => sourcePackageOf(p) == selection.package)
          .toList();
    }
    return notRefused.toList();
  }

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