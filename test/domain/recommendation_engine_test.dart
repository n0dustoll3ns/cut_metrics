import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/recommendation_engine.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/domain/weekly_energy_stats.dart';
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

  // ==========================================================================
  // ФАЗА 7, C.2 — движок v2 (энергостаты + конкретные ккал + дельта §0 п.13)
  // ==========================================================================

  group('compute v2 (Фаза 7, C.2)', () {
    // Дельта для 100 кг и |цель−факт| × 11 всегда упирается в потолок 300,
    // кроме случаев крошечной разницы — для тестов берём потолок.
    final stats = WeeklyEnergyStats(
      avgIntake: 2150,
      intakeDays: 6,
      avgExpenditure: 2680,
      avgBalance: -530,
      expectedKgPerWeek: -0.48,
    );

    test('регресс: без energyStats — тексты Фазы 5 дословно (все 3 статуса)', () {
      // tooSlow
      final slow = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: emaCacheOf([(0, 99.7), (2, 99.8), (4, 99.9), (6, 100.0)]),
        today: DateTime.now(),
        targetPacePercent: 0.8,
      )!;
      expect(
        slow.recommendationText,
        'Темп 0.3%/нед ниже цели 0.8%/нед. '
        'Снизь калорийность на ~100 ккал в сутки.',
      );

      // inPace (pace −0.7)
      final ok = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: emaCacheOf([(0, 99.4), (2, 99.6), (4, 99.8), (6, 100.0)]),
        today: DateTime.now(),
        targetPacePercent: 0.8,
      )!;
      expect(
        ok.recommendationText,
        'Темп 0.7%/нед при цели 0.8%/нед. '
        'Оставь текущую калорийность без изменений.',
      );

      // tooFast (pace −2.92)
      final fast = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: emaCacheOf([(0, 97.5), (2, 98.3), (4, 99.2), (6, 100.0)]),
        today: DateTime.now(),
        targetPacePercent: 0.8,
      )!;
      expect(
        fast.recommendationText,
        'Темп 2.9%/нед выше цели 0.8%/нед. '
        'Добавь ~150–200 ккал в сутки, чтобы вернуться в целевой темп.',
      );
    });

    test('v2 tooSlow: {intakeNew} = {intake} − {delta} (потолок 300)', () {
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: emaCacheOf([(0, 99.7), (2, 99.8), (4, 99.9), (6, 100.0)]),
        today: DateTime.now(),
        targetPacePercent: 0.8,
        energyStats: stats,
      )!;
      expect(s.status, PaceStatus.tooSlow);
      expect(
        s.recommendationText,
        'Темп 0.3%/нед ниже цели 0.8%/нед. Средний приход 2150 ккал/день — '
        'снизь до 1850 (−300 ккал).',
      );
    });

    test('v2 tooFast: {intakeNew} = {intake} + {delta}', () {
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: emaCacheOf([(0, 97.5), (2, 98.3), (4, 99.2), (6, 100.0)]),
        today: DateTime.now(),
        targetPacePercent: 0.8,
        energyStats: stats,
      )!;
      expect(s.status, PaceStatus.tooFast);
      expect(
        s.recommendationText,
        'Темп 2.9%/нед выше цели 0.8%/нед. Средний приход 2150 ккал/день — '
        'добавь до 2450 (+300 ккал).',
      );
    });

    test('v2 inPace: баланс подставлен со знаком', () {
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: emaCacheOf([(0, 99.4), (2, 99.6), (4, 99.8), (6, 100.0)]),
        today: DateTime.now(),
        targetPacePercent: 0.8,
        energyStats: stats,
      )!;
      expect(s.status, PaceStatus.inPace);
      expect(
        s.recommendationText,
        'Держишь дефицит −530 ккал/день — темп 0.7%/нед в цели. '
        'Оставь рацион без изменений.',
      );
    });

    test('v2 inPace при null-балансе — фолбэк на текст Фазы 5', () {
      final noBalance = WeeklyEnergyStats(
        avgIntake: 2150,
        intakeDays: 6,
        avgExpenditure: null,
        avgBalance: null,
        expectedKgPerWeek: null,
      );
      final s = RecommendationEngine.compute(
        weightCache: weightCache,
        emaCache: emaCacheOf([(0, 99.4), (2, 99.6), (4, 99.8), (6, 100.0)]),
        today: DateTime.now(),
        targetPacePercent: 0.8,
        energyStats: noBalance,
      )!;
      expect(
        s.recommendationText,
        'Темп 0.7%/нед при цели 0.8%/нед. '
        'Оставь текущую калорийность без изменений.',
      );
    });

    test('числа «как есть»: дробный приход — 1 знак, дельта — до 10', () {
      // Вес 60 кг, факт 0.7 vs цель 0.8: 60 × 0.1 × 11 = 66 → 70 (округление).
      final w60 = weightCacheOf([(0, 60.0), (2, 59.9), (4, 59.8), (6, 59.7)]);
      final frac = WeeklyEnergyStats(
        avgIntake: 2150 + 1.0 / 3,
        intakeDays: 6,
        avgExpenditure: 2680,
        avgBalance: -530,
        expectedKgPerWeek: -0.48,
      );
      final s = RecommendationEngine.compute(
        weightCache: w60,
        emaCache: emaCacheOf([(0, 59.7), (2, 59.8), (4, 59.9), (6, 60.0)]),
        today: DateTime.now(),
        targetPacePercent: 0.8,
        energyStats: frac,
      )!;
      // pace: (59.7−60)/60 × 7/6 = −0.58; |−0.58 − 0.8| = 1.38 →
      // 60 × 1.38 × 11 = 913 → потолок 300.
      expect(
        s.recommendationText,
        'Темп 0.6%/нед ниже цели 0.8%/нед. Средний приход 2150.3 ккал/день — '
        'снизь до 1850.3 (−300 ккал).',
      );
    });
  });

  group('правило «после последнего 5+-дневного разрыва» (2026-09-16)', () {
    test('разрыв 5 дней в окне: точек после отсечения меньше 3 => null', () {
      // Веса offsets 0 и 6 — между ними 5 пустых дней (разрыв серии);
      // после отсечения остаётся 1 EMA-точка — саммари не готово.
      final weights = weightCacheOf([(0, 99.0), (6, 100.0)]);
      final ema = emaCacheOf([(0, 99.0), (6, 100.0)]);
      expect(
        RecommendationEngine.compute(
          weightCache: weights,
          emaCache: ema,
          today: DateTime.now(),
          targetPacePercent: 0.8,
        ),
        isNull,
      );
    });
  });
}
