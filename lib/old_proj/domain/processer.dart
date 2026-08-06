import 'package:equatable/equatable.dart';
import 'package:health/health.dart';
import 'package:cut_metrics/old_proj/domain/date_extension.dart';
import 'package:cut_metrics/old_proj/domain/weight.dart';
import 'package:cut_metrics/old_proj/domain/sleep.dart';
import 'package:cut_metrics/old_proj/domain/nutrition.dart';
import 'package:cut_metrics/old_proj/domain.dart';

/// Слой бизнес-логики: агрегирует сырые точки в модели для графиков.
/// Не знает об UI, не хранит состояние.
class HealthDataProcessor {
  // ─── Приоритет источников ────────────────────────────────────────────────────

  /// Возвращает приоритет источника: 0 = наивысший.
  /// Неизвестный источник получает низший приоритет (length списка).
  /// Если список приоритетов пуст — все источники равны (возврат 0).
  int getSourcePriority(String? source, List<String> sourcePriorities) {
    if (source == null || sourcePriorities.isEmpty) return 0;
    final idx = sourcePriorities.indexOf(source);
    return idx == -1 ? sourcePriorities.length : idx;
  }

  /// Для каждого дня оставляет только точки из источника с наивысшим приоритетом.
  /// Если приоритеты пусты — возвращает все точки без изменений.
  List<HealthDataPoint> filterByTopSource(
    List<HealthDataPoint> points,
    List<String> sourcePriorities,
  ) {
    if (sourcePriorities.isEmpty) return points;

    // Группируем точки по дню → по источнику
    final byDay = <DateKey, Map<String, List<HealthDataPoint>>>{};
    for (final p in points) {
      final key = DateKey(p.dateFrom);
      final src = p.sourceId;
      byDay.putIfAbsent(key, () => {}).putIfAbsent(src, () => []).add(p);
    }

    final result = <HealthDataPoint>[];
    for (final sourcesMap in byDay.values) {
      if (sourcesMap.length <= 1) {
        // Один источник за день — берём все его точки
        result.addAll(sourcesMap.values.first);
        continue;
      }
      // Несколько источников — выбираем лучший
      String? bestSource;
      int bestPrio = sourcePriorities.length + 1;
      for (final src in sourcesMap.keys) {
        final prio = getSourcePriority(src, sourcePriorities);
        if (prio < bestPrio) {
          bestSource = src;
          bestPrio = prio;
        }
      }
      result.addAll(sourcesMap[bestSource]!);
    }
    return result;
  }

  // ─── Вес ────────────────────────────────────────────────────────────────────

  /// Добавляет новые точки веса в кеш.
  /// РЕФАКТОРИНГ: если за день несколько измерений — берём последнее по времени
  /// (а не первое пришедшее, как раньше через containsKey-continue).
  void mergeWeightInto(
    Map<DateKey, WeightDay> cache,
    List<HealthDataPoint> points,
    List<String> sourcePriorities,
  ) {
    // Фильтруем: один (лучший) источник на каждый день
    final filtered = filterByTopSource(points, sourcePriorities);
    // Сортируем по времени, чтобы последнее измерение дня перезаписало предыдущее
    final sorted = [...filtered]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    for (final p in sorted) {
      final key = DateKey(p.dateFrom);
      final v = p.value;
      if (v is NumericHealthValue) {
        // Перезаписываем — побеждает последнее измерение дня
        cache[key] = WeightDay(date: key, weight: v.numericValue.toDouble());
      }
    }
  }

  /// Пересчитывает EMA по всему кешу весов и возвращает новый кеш EMA.
  Map<DateKey, WeightDay> computeEma(Map<DateKey, WeightDay> weightCache, int period) {
    if (weightCache.isEmpty) return {};

    final sorted = weightCache.values.toList()..sort((a, b) => a.date.compareTo(b.date));

    final multiplier = 2 / (period + 1);
    double ema = sorted.first.weight;

    final result = <WeightDay>[WeightDay(date: sorted.first.date, weight: ema)];
    for (int i = 1; i < sorted.length; i++) {
      ema = (sorted[i].weight - ema) * multiplier + ema;
      result.add(WeightDay(date: sorted[i].date, weight: ema));
    }

    return Map.fromEntries(result.map((e) => MapEntry(e.date, e)));
  }

  // ─── Шаги ───────────────────────────────────────────────────────────────────

  /// Добавляет новые точки шагов в существующий кеш (суммирует за день).
  void mergeStepsInto(
    Map<DateKey, StepsDay> cache,
    List<HealthDataPoint> points,
    List<String> sourcePriorities,
  ) {
    // Фильтруем: один (лучший) источник на каждый день
    final filtered = filterByTopSource(points, sourcePriorities);
    for (final p in filtered) {
      final key = DateKey(p.dateFrom);
      final v = p.value;
      if (v is NumericHealthValue) {
        final steps = v.numericValue.toInt();
        cache[key] = cache[key]?.copyWithAddedSteps(steps: steps) ?? StepsDay(date: key, steps: steps);
      }
    }
  }

  // ─── Питание ────────────────────────────────────────────────────────────────

  /// Промежуточная модель: одна сырая точка питания (продукт)
  List<_NutritionEntry> _convertToEntries(List<HealthDataPoint> points) {
    final entries = <_NutritionEntry>[];
    for (final p in points) {
      final v = p.value;
      if (v is! NutritionHealthValue) continue;
      final cal = v.calories?.toDouble() ?? 0;
      final prot = v.protein?.toDouble() ?? 0;
      final fat = v.fat?.toDouble() ?? 0;
      final carbs = v.carbs?.toDouble() ?? 0;

      // Фильтр мусора
      if (cal == 0 && prot == 0 && fat == 0 && carbs == 0) continue;

      entries.add(
        _NutritionEntry(
          sourceBundleId: p.sourceId,
          startTime: p.dateFrom,
          calories: cal,
          protein: prot,
          fat: fat,
          carbs: carbs,
        ),
      );
    }
    return entries;
  }

  /// Промежуточная модель: сгруппированный приём пищи (кластер)
  List<MealSession> _clusterEntries(List<_NutritionEntry> entries) {
    if (entries.isEmpty) return [];

    // Сортируем по источнику и времени
    entries.sort((a, b) {
      final srcCmp = a.sourceBundleId.compareTo(b.sourceBundleId);
      if (srcCmp != 0) return srcCmp;
      return a.startTime.compareTo(b.startTime);
    });

    final sessions = <MealSession>[];
    var currentBatch = <_NutritionEntry>[];
    DateTime? batchEndTime;

    void flushBatch() {
      if (currentBatch.isEmpty) return;
      final start = currentBatch.first.startTime;
      final end = currentBatch.last.startTime;
      final totalCal = currentBatch.fold(0.0, (s, e) => s + e.calories);
      final totalProt = currentBatch.fold(0.0, (s, e) => s + e.protein);
      final totalFat = currentBatch.fold(0.0, (s, e) => s + e.fat);
      final totalCarbs = currentBatch.fold(0.0, (s, e) => s + e.carbs);

      sessions.add(
        MealSession(
          sourceBundleId: currentBatch.first.sourceBundleId,
          startTime: start,
          endTime: end,
          calories: totalCal,
          protein: totalProt,
          fat: totalFat,
          carbs: totalCarbs,
        ),
      );
      currentBatch = [];
      batchEndTime = null;
    }

    for (final entry in entries) {
      if (currentBatch.isEmpty) {
        currentBatch.add(entry);
        batchEndTime = entry.startTime;
        continue;
      }

      final isSameSource = entry.sourceBundleId == currentBatch.first.sourceBundleId;
      final diffMinutes = entry.startTime.difference(batchEndTime!).inMinutes.abs();

      if (isSameSource && diffMinutes <= _mealGapMinutes) {
        currentBatch.add(entry);
        batchEndTime = entry.startTime;
      } else {
        flushBatch();
        currentBatch.add(entry);
        batchEndTime = entry.startTime;
      }
    }
    flushBatch();

    return sessions;
  }

  /// Агрегация кластеров в NutritionDay.
  NutritionDay aggregateNutritionDay(
    DateKey date,
    List<MealSession> sessions,
  ) {
    double totalCal = 0, totalProt = 0, totalFat = 0, totalCarbs = 0;
    for (final s in sessions) {
      totalCal += s.calories;
      totalProt += s.protein;
      totalFat += s.fat;
      totalCarbs += s.carbs;
    }
    return NutritionDay(date: date, calories: totalCal, protein: totalProt, fat: totalFat, carbs: totalCarbs);
  }

  /// Порог для fuzzy matching (больше не используется для cross-source dedup,
  /// но может пригодиться для внутриисточниковой дедупликации).
  static const _mealGapMinutes = 30; // Максимальный интервал между продуктами в одном приёме пищи

  /// Обновляет кеш сырых точек питания.
  /// Фильтрует по лучшему источнику за день, затем кластеризует.
  void mergeNutritionInto(
    Map<DateKey, List<MealSession>> cache,
    List<HealthDataPoint> points,
    List<String> sourcePriorities,
  ) {
    // Группируем сырые точки по дням
    final byDay = <DateKey, List<HealthDataPoint>>{};
    for (final p in points) {
      final key = DateKey(p.dateFrom);
      byDay.putIfAbsent(key, () => []).add(p);
    }

    for (final entry in byDay.entries) {
      final dayKey = entry.key;
      // 0. Фильтруем: один (лучший) источник за день
      final filteredPoints = filterByTopSource(entry.value, sourcePriorities);
      // 1. Конвертация
      final newEntries = _convertToEntries(filteredPoints);
      // 2. Кластеризация новых точек
      final newSessions = _clusterEntries(newEntries);

      // Сливаем с существующими в кеше и перезаписываем
      // (т.к. теперь все сессии из одного источника, cross-source dedup не нужен)
      cache[dayKey] = newSessions;
    }
  }

  // ─── Сон ────────────────────────────────────────────────────────────────────

  /// Обрабатывает сон и добавляет результат в существующий кеш.
  void mergeSleepInto(
    Map<DateKey, SleepDay> cache,
    List<HealthDataPoint> points,
    DateTime rangeStart,
    DateTime rangeEnd,
    List<String> sourcePriorities,
  ) {
    final analyzer = SleepAnalyzer();
    final days = analyzer.processSleepData(
      rawPoints: points,
      daysToAnalyze: rangeEnd.difference(rangeStart).inDays,
      now: rangeEnd,
      sourcePriorities: sourcePriorities,
    );
    for (final day in days) {
      cache.putIfAbsent(day.date, () => day);
    }
  }
}

/// Промежуточная модель: одна сырая точка питания (продукт)
class _NutritionEntry extends Equatable {
  final String sourceBundleId;
  final DateTime startTime;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;

  const _NutritionEntry({
    required this.sourceBundleId,
    required this.startTime,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  @override
  List<Object?> get props => [sourceBundleId, startTime, calories, protein, fat, carbs];
}

/// Промежуточная модель: сгруппированный приём пищи (кластер)
class MealSession extends Equatable {
  final String sourceBundleId;
  final DateTime startTime;
  final DateTime endTime;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;

  const MealSession({
    required this.sourceBundleId,
    required this.startTime,
    required this.endTime,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  @override
  List<Object?> get props => [sourceBundleId, startTime, endTime, calories, protein, fat, carbs];
}