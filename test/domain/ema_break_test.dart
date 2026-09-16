import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:flutter_test/flutter_test.dart';

/// Правило разрыва EMA (решение пользователя 2026-09-16): 5 и более
/// ПОДРЯД пустых дней между взвешиваниями обрывают серию — новое
/// скользящее стартует заново (инициализация весом точки после разрыва);
/// пропуски 1–4 дня EMA «тянет» через себя как обычно.
void main() {
  final processor = HealthDataProcessor(appPackageId: 'com.example.cut_metrics');

  DateKey key(String iso) => DateKey(DateTime.parse(iso));

  Map<DateKey, WeightDay> cacheOf(Map<String, double> weights) => {
        for (final e in weights.entries)
          key(e.key): WeightDay(
            date: key(e.key),
            weight: e.value,
            source: DataSource.external,
          ),
      };

  group('computeEma: разрыв при пустотах (2026-09-16)', () {
    test('порог — RecommendationConfig.emaBreakGapDays = 5', () {
      expect(RecommendationConfig.emaBreakGapDays, 5);
    });

    test('подряд идущие дни — обычная формула', () {
      final ema = processor.computeEma(cacheOf({'2026-01-01': 100, '2026-01-02': 80}), 7);
      final m = 2 / (7 + 1);
      expect(ema[key('2026-01-02')]!.weight, closeTo(100 - 20 * m, 1e-9));
    });

    test('пропуск 4 дня — EMA продолжается обычной формулой', () {
      // 1-е и 6-е число: между ними 4 пустых дня — меньше порога.
      final ema = processor.computeEma(cacheOf({'2026-01-01': 100, '2026-01-06': 80}), 7);
      final m = 2 / (7 + 1);
      expect(ema[key('2026-01-06')]!.weight, closeTo(100 - 20 * m, 1e-9));
    });

    test('пропуск 5 дней — серия обрывается, EMA = вес точки после разрыва', () {
      // 1-е и 7-е число: между ними 5 пустых дней — рестарт серии.
      final ema = processor.computeEma(cacheOf({'2026-01-01': 100, '2026-01-07': 80}), 7);
      expect(ema[key('2026-01-07')]!.weight, 80.0);
    });

    test('разрыв 6 дней — рестарт (выше порога)', () {
      final ema = processor.computeEma(cacheOf({'2026-01-01': 100, '2026-01-08': 90}), 7);
      expect(ema[key('2026-01-08')]!.weight, 90.0);
    });

    test('после рестарта серия продолжается обычной формулой', () {
      final ema = processor.computeEma(
        cacheOf({'2026-01-01': 100, '2026-01-07': 80, '2026-01-08': 60}),
        7,
      );
      final m = 2 / (7 + 1);
      expect(ema[key('2026-01-07')]!.weight, 80.0);
      expect(ema[key('2026-01-08')]!.weight, closeTo(80 - 20 * m, 1e-9));
    });
  });
}
