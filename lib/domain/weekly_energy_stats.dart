import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/domain/gap_rule.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';

/// Энергостаты за скользящее окно (Фаза 7, C.1) — данные для карточки
/// «Энергобаланс недели» и движка рекомендаций v2.
///
/// Окно = последние 7 дней **исключая сегодня** (A.8): `today−6 .. today−1`
/// (6 полных дней). «Сегодня» не входит — день ещё не завершён, приход/расход
/// неполные; запись веса за сегодня, наоборот, валидна (для веса своё правило).
///
/// Знаменатели средних — только дни с данными соответствующего типа:
/// - [avgIntake] — по дням с приходом ([intakeDays], покрытие 0–6);
/// - [avgExpenditure] — по дням с расходом (BMR рассчитан);
/// - [avgBalance] — только по дням, где есть И приход, И расход (из A.4 п.4
///   «баланс за день не считается» без расхода).
class WeeklyEnergyStats {
  /// Средний приход, ккал/день — по [intakeDays] дням с приходом.
  final double avgIntake;

  /// Дней с приходом в окне (покрытие «по N из 6»), 0–6.
  final int intakeDays;

  /// Средний расход, ккал/день — по дням с расходом; `null` — расхода нет.
  final double? avgExpenditure;

  /// Средний баланс, ккал/день — по дням с приходом И расходом;
  /// `null` — таких дней нет (расход не рассчитан ни в один день).
  final double? avgBalance;

  /// Ожидаемый темп из баланса: `avgBalance × 7 / 7700`, кг/нед (со знаком);
  /// `null` при [avgBalance] == null. Отрицательный = снижение.
  final double? expectedKgPerWeek;

  const WeeklyEnergyStats({
    required this.avgIntake,
    required this.intakeDays,
    required this.avgExpenditure,
    required this.avgBalance,
    required this.expectedKgPerWeek,
  });

  @override
  String toString() =>
      'WeeklyEnergyStats(приход: ${avgIntake.toStringAsFixed(0)} × $intakeDays дн., '
      'расход: ${avgExpenditure?.toStringAsFixed(0) ?? '—'}, '
      'баланс: ${avgBalance?.toStringAsFixed(0) ?? '—'}, '
      'ожидание: ${expectedKgPerWeek?.toStringAsFixed(2) ?? '—'} кг/нед)';
}

/// Считает энергостаты за окно `today−6 .. today−1` из кешей.
///
/// `null` — дней с приходом < 2 (C.1): энергоблок скрыт, движок работает по
/// старым текстам Фазы 5. Чистый Dart, кеши уже резолвлены процессором.
///
/// (Имя отличается от `DashboardViewModel.computeWeeklyEnergyStats` —
/// метод VM делегирует сюда; одно имя внутри класса затеняло бы функцию.)
WeeklyEnergyStats? computeEnergyStats({
  required Map<DateKey, NutritionDay> nutritionCache,
  required Map<DateKey, ExpenditureDay> expenditureCache,
  required DateTime today,
}) {
  final windowStart = DateKey(today.subtract(const Duration(days: 6)));
  final windowEnd = DateKey(today.subtract(const Duration(days: 1)));

  bool inWindow(DateKey k) =>
      !k.value.isBefore(windowStart.value) && !k.value.isAfter(windowEnd.value);

  // Правило «после последнего 5+-дневного разрыва» (2026-09-16): каждая
 // метрика отсекается по СВОИМ данным (приход — по приходу, расход — по
 // расходу), баланс — по дням, прошедшим оба отсечения. При текущем
 // окне в 6 дней разрыв 5+ внутри окна невозможен — это защита на случай
 // расширения окна и консистентность с остальными средними.
 final intakeDays = daysAfterLastGap(nutritionCache.keys.where(inWindow)).toList();
  if (intakeDays.length < 2) return null;

  final avgIntake =
      intakeDays.map((k) => nutritionCache[k]!.calories).reduce((a, b) => a + b) /
          intakeDays.length;

  final expDays = daysAfterLastGap(expenditureCache.keys.where(inWindow)).toList();
  final double? avgExpenditure = expDays.isEmpty
      ? null
      : expDays.map((k) => expenditureCache[k]!.total).reduce((a, b) => a + b) /
            expDays.length;

  // Баланс — только дни, где есть и приход, и расход.
  final balanceDays = intakeDays
      .where((k) => expenditureCache.containsKey(k) && expDays.contains(k))
      .toList();
  final double? avgBalance = balanceDays.isEmpty
      ? null
      : balanceDays
            .map((k) => nutritionCache[k]!.calories - expenditureCache[k]!.total)
            .reduce((a, b) => a + b) /
            balanceDays.length;

  final expectedKgPerWeek =
      avgBalance == null ? null : avgBalance * 7 / ExpenditureConfig.kcalPerKgFat;

  return WeeklyEnergyStats(
    avgIntake: avgIntake,
    intakeDays: intakeDays.length,
    avgExpenditure: avgExpenditure,
    avgBalance: avgBalance,
    expectedKgPerWeek: expectedKgPerWeek,
  );
}
