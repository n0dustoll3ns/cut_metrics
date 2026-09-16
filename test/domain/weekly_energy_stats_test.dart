import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';
import 'package:cut_metrics/domain/weekly_energy_stats.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тесты энергостатов за скользящее окно (Фаза 7, C.1 / DoD C.4).
void main() {
  final today = DateTime(2026, 7, 24);

  DateKey day(int offset) => DateKey(today.subtract(Duration(days: offset)));

  NutritionDay nutrition(int offset, double kcal) => NutritionDay(
        date: day(offset),
        calories: kcal,
        source: DataSource.external,
      );

  ExpenditureDay expenditure(int offset, double total) => ExpenditureDay(
        date: day(offset),
        bmrKcal: total,
        stepsKcal: 0,
        trainingKcal: 0,
        householdKcal: 0,
      );

  group('computeEnergyStats (окно today−6..today−1, A.8/C.1)', () {
    test('«сегодня» и дни старше 6 не входят в окно', () {
      final stats = computeEnergyStats(
        nutritionCache: {
          day(0): nutrition(0, 9999), // сегодня — исключён
          day(1): nutrition(1, 2000),
          day(2): nutrition(2, 2000),
          day(7): nutrition(7, 8888), // старше окна
        },
        expenditureCache: const {},
        today: today,
      );
      // В окне 2 дня с приходом (1 и 2) → ок; 2000 не испорчены крайними.
      expect(stats!.intakeDays, 2);
      expect(stats.avgIntake, 2000);
    });

    test('меньше 2 дней с приходом → null', () {
      expect(
        computeEnergyStats(
          nutritionCache: {day(1): nutrition(1, 2000)},
          expenditureCache: const {},
          today: today,
        ),
        isNull,
      );
      expect(
        computeEnergyStats(nutritionCache: const {}, expenditureCache: const {}, today: today),
        isNull,
      );
    });

    test('avgIntake — по дням с приходом; avgExpenditure — по дням с расходом', () {
      final stats = computeEnergyStats(
        nutritionCache: {
          day(1): nutrition(1, 2000),
          day(2): nutrition(2, 2400),
          day(3): nutrition(3, 1900),
        },
        expenditureCache: {
          day(1): expenditure(1, 2600),
          day(2): expenditure(2, 2700),
          day(4): expenditure(4, 2800), // без прихода — только в расходе
        },
        today: today,
      );
      expect(stats!.intakeDays, 3);
      expect(stats.avgIntake, closeTo((2000 + 2400 + 1900) / 3, 1e-9));
      expect(stats.avgExpenditure, closeTo((2600 + 2700 + 2800) / 3, 1e-9));
      // Баланс — только дни 1 и 2 (есть и приход, и расход).
      expect(stats.avgBalance, closeTo(((2000 - 2600) + (2400 - 2700)) / 2, 1e-9));
      expect(stats.expectedKgPerWeek, closeTo(stats.avgBalance! * 7 / 7700, 1e-9));
    });

    test('расхода нет ни в один день → avgExpenditure/avgBalance/ожидание null', () {
      final stats = computeEnergyStats(
        nutritionCache: {day(1): nutrition(1, 2000), day(2): nutrition(2, 2400)},
        expenditureCache: const {},
        today: today,
      );
      expect(stats!.avgExpenditure, isNull);
      expect(stats.avgBalance, isNull);
      expect(stats.expectedKgPerWeek, isNull);
      expect(stats.avgIntake, 2200);
    });

    test('покрытие прихода 0–6 (intakeDays)', () {
      final nutritionCache = <DateKey, NutritionDay>{
        for (var i = 1; i <= 6; i++) day(i): nutrition(i, 2000),
      };
      final stats = computeEnergyStats(
        nutritionCache: nutritionCache,
        expenditureCache: const {},
        today: today,
      );
      expect(stats!.intakeDays, 6);
    });
  });
}
