import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/recommendation_engine.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:flutter_test/flutter_test.dart';

/// Хелпер: кеш веса из списка (dayOffset, вес) — резолвленные точки.
Map<DateKey, WeightDay> weightCacheOf(List<(int, double)> dayOffsetWeight) {
  final now = DateTime.now();
  return {
    for (final (offset, w) in dayOffsetWeight)
      DateKey(now.subtract(Duration(days: offset))): WeightDay(
        date: DateKey(now.subtract(Duration(days: offset))),
        weight: w,
        source: DataSource.external,
      ),
  };
}

/// Хелпер: EMA-кеш — подставные EMA-точки (движок принимает EMA предрассчитанным).
Map<DateKey, WeightDay> emaCacheOf(List<(int, double)> dayOffsetEma) {
  final now = DateTime.now();
  return {
    for (final (offset, e) in dayOffsetEma)
      DateKey(now.subtract(Duration(days: offset))): WeightDay(
        date: DateKey(now.subtract(Duration(days: offset))),
        weight: e,
        source: DataSource.external,
      ),
  };
}

void main() {
  // Кеш с 4 точками в окне (минимум для расчёта — 3).
  final weightCache = weightCacheOf([(0, 100.0), (2, 99.8), (4, 99.6), (6, 99.4)]);

  group('compute: три статуса (A.3)', () {
    test('tooSlow: фактический темп заметно ниже цели', () {
      // EMA: 100 → 99.7 за 6 дней: raw = −0.3%, pace = −0.3 × 7/6 ≈ −0.35.
      final ema = emaCacheOf([(0, 99.7), (2, 99.8), (4, 99.9), (6, 100.0)]);
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: ema,
        today: DateTime.now(),
        targetPacePercent: 0.8,
      )!;
      expect(s.status, PaceStatus.tooSlow);
      expect(s.actualPacePercent, closeTo(-0.35, 1e-9));
    });

    test('inPace: фактический темп внутри допуска', () {
      // EMA: 100 → 99.4: raw = −0.6%, pace = −0.7. |−0.7 − 0.8| = 0.1 ≤ 0.15.
      final ema = emaCacheOf([(0, 99.4), (2, 99.6), (4, 99.8), (6, 100.0)]);
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: ema,
        today: DateTime.now(),
        targetPacePercent: 0.8,
      )!;
      expect(s.status, PaceStatus.inPace);
      expect(s.actualPacePercent, closeTo(-0.7, 1e-9));
    });

    test('tooFast: фактический темп заметно выше цели', () {
      // EMA: 100 → 99.0: raw = −1.0%, pace ≈ −1.1667. |pace| − 0.8 ≈ 0.37 > 0.15.
      final ema = emaCacheOf([(0, 99.0), (2, 99.3), (4, 99.7), (6, 100.0)]);
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: ema,
        today: DateTime.now(),
        targetPacePercent: 0.8,
      )!;
      expect(s.status, PaceStatus.tooFast);
    });
  });

  group('compute: границы допуска', () {
    test('diff ровно = tolerance → inPace (граница включительно)', () {
      // Нулевой темп, цель 0.8, tolerance 0.8 → |0 − 0.8| = 0.8 ≤ 0.8.
      final ema = emaCacheOf([(0, 100.0), (2, 100.0), (4, 100.0), (6, 100.0)]);
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: ema,
        today: DateTime.now(),
        targetPacePercent: 0.8,
        tolerance: 0.8,
      )!;
      expect(s.status, PaceStatus.inPace);
    });

    test('чуть за границей tolerance → tooSlow', () {
      final ema = emaCacheOf([(0, 100.0), (2, 100.0), (4, 100.0), (6, 100.0)]);
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: ema,
        today: DateTime.now(),
        targetPacePercent: 0.8,
        tolerance: 0.79,
      )!;
      expect(s.status, PaceStatus.tooSlow);
    });
  });

  group('compute: нормализация к неделе (уточнение A.3)', () {
    test('темп за 2 дня экстраполируется на 7', () {
      // EMA: 100 → 99.9 за 2 дня: raw = −0.1%, pace = −0.1 × 7/2 = −0.35.
      final ema = emaCacheOf([(0, 99.9), (1, 99.95), (2, 100.0)]);
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: ema,
        today: DateTime.now(),
        targetPacePercent: 0.8,
      )!;
      expect(s.actualPacePercent, closeTo(-0.35, 1e-9));
    });
  });

  group('compute: недостаточность данных', () {
    test('меньше 3 точек веса в окне → null', () {
      final small = weightCacheOf([(0, 100.0), (3, 99.5)]);
      final ema = emaCacheOf([(0, 99.5), (3, 100.0)]);
      expect(
        RecommendationEngine.compute(
          weightCache: small,
          emaCache: ema,
          today: DateTime.now(),
          targetPacePercent: 0.8,
        ),
        isNull,
      );
    });

    test('менее 2 EMA-точек в окне → null', () {
      final ema = emaCacheOf([(0, 100.0)]);
      expect(
        RecommendationEngine.compute(
          weightCache: weightCache,
          emaCache: ema,
          today: DateTime.now(),
          targetPacePercent: 0.8,
        ),
        isNull,
      );
    });

    test('точки вне окна не учитываются', () {
      final old = weightCacheOf([(10, 100.0), (12, 99.5), (14, 99.0)]);
      expect(
        RecommendationEngine.compute(
          weightCache: old,
          emaCache: emaCacheOf([(10, 99.0), (14, 100.0)]),
          today: DateTime.now(),
          targetPacePercent: 0.8,
        ),
        isNull,
      );
    });
  });
}
