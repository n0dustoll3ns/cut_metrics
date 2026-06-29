import 'package:health/health.dart';
import 'package:cut_metrics/domain/date_extension.dart';
import 'package:cut_metrics/domain/weight.dart';
import 'package:cut_metrics/domain/sleep.dart';
import 'package:cut_metrics/domain/nutrition.dart';
import 'package:cut_metrics/domain.dart';

/// Слой бизнес-логики: агрегирует сырые точки в модели для графиков.
/// Не знает об UI, не хранит состояние.
class HealthDataProcessor {
  // ─── Вес ────────────────────────────────────────────────────────────────────

  /// Добавляет новые точки веса в кеш.
  /// РЕФАКТОРИНГ: если за день несколько измерений — берём последнее по времени
  /// (а не первое пришедшее, как раньше через containsKey-continue).
  void mergeWeightInto(
    Map<DateKey, WeightDay> cache,
    List<HealthDataPoint> points,
  ) {
    // Сортируем по времени, чтобы последнее измерение дня перезаписало предыдущее
    final sorted = [...points]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
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
  Map<DateKey, WeightDay> computeEma(
    Map<DateKey, WeightDay> weightCache,
    int period,
  ) {
    if (weightCache.isEmpty) return {};

    final sorted = weightCache.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

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
  ) {
    for (final p in points) {
      final key = DateKey(p.dateFrom);
      final v = p.value;
      if (v is NumericHealthValue) {
        final steps = v.numericValue.toInt();
        cache[key] = cache[key]?.copyWithAddedSteps(steps: steps) ??
            StepsDay(date: key, steps: steps);
      }
    }
  }

  // ─── Питание ────────────────────────────────────────────────────────────────

  /// Добавляет новые точки питания в существующий кеш.
  void mergeNutritionInto(
    Map<DateKey, NutritionDay> cache,
    List<HealthDataPoint> points,
  ) {
    for (final p in points) {
      final key = DateKey(p.dateFrom);
      if (cache.containsKey(key)) continue;
      final v = p.value;
      if (v is NutritionHealthValue) {
        cache[key] = NutritionDay(
          date: key,
          calories: v.calories?.toDouble() ?? 0,
          protein: v.protein?.toDouble() ?? 0,
          fat: v.fat?.toDouble() ?? 0,
          carbs: v.carbs?.toDouble() ?? 0,
        );
      }
    }
  }

  // ─── Сон ────────────────────────────────────────────────────────────────────

  /// Обрабатывает сон и добавляет результат в существующий кеш.
  void mergeSleepInto(
    Map<DateKey, SleepDay> cache,
    List<HealthDataPoint> points,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final analyzer = SleepAnalyzer();
    final days = analyzer.processSleepData(
      rawPoints: points,
      daysToAnalyze: rangeEnd.difference(rangeStart).inDays,
      now: rangeEnd,
    );
    for (final day in days) {
      cache.putIfAbsent(day.date, () => day);
    }
  }
}