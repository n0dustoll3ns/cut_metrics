import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/domain/gap_rule.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';

/// Строка таблицы дней окна энергобаланса — для трассы «Энергобаланс недели»
/// (CalcDetail §3.7, решение пользователя «вариант A»: единый источник истины,
/// значения не пересчитываются второй раз).
///
/// Строка есть для каждого дня окна, где есть приход ИЛИ расход. День без
/// расхода — [balanceKcal] == `null`, «баланс не считается» (A.4 п.4).
class EnergyDayRow {
  final DateKey date;

  /// Приход, ккал; `null` — дня нет в кеше питания («нет данных ≠ 0»).
  final double? intakeKcal;

  /// Расход, ккал; `null` — BMR не рассчитан.
  final double? expenditureKcal;

  /// Баланс `приход − расход`; `null` — одного из слагаемых нет.
  final double? balanceKcal;

  const EnergyDayRow({
    required this.date,
    this.intakeKcal,
    this.expenditureKcal,
    this.balanceKcal,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnergyDayRow &&
          date == other.date &&
          intakeKcal == other.intakeKcal &&
          expenditureKcal == other.expenditureKcal &&
          balanceKcal == other.balanceKcal;

  @override
  int get hashCode => Object.hash(date, intakeKcal, expenditureKcal, balanceKcal);

  @override
  String toString() =>
      'EnergyDayRow($date, приход: ${intakeKcal?.toStringAsFixed(0) ?? '—'}, '
      'расход: ${expenditureKcal?.toStringAsFixed(0) ?? '—'}, '
      'баланс: ${balanceKcal?.toStringAsFixed(0) ?? '—'})';
}

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

  /// Таблица дней окна для трассы «Энергобаланс недели» (CalcDetail §3.7,
  /// «вариант A»): день · приход · расход · баланс. Строки для всех дней окна
  /// с приходом или расходом; день без расхода — баланс `null` («баланс не
  /// считается», A.4 п.4). Средние выше считаются по своим знаменателям —
  /// при окне в 6 дней правило «после разрыва» отсечений не даёт, значения
  /// строки и средних консистентны.
  final List<EnergyDayRow> dayRows;

  const WeeklyEnergyStats({
    required this.avgIntake,
    required this.intakeDays,
    required this.avgExpenditure,
    required this.avgBalance,
    required this.expectedKgPerWeek,
    this.dayRows = const [],
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

  // Таблица дней окна (CalcDetail §3.7): строки не пересчитывают средние —
  // это те же кеши, прочитанные по дням; средние выше — по своим знаменателям.
  final rows = <EnergyDayRow>[];
  for (var i = 6; i >= 1; i--) {
    final k = DateKey(today.subtract(Duration(days: i)));
    if (!inWindow(k)) continue;
    final intake = nutritionCache[k]?.calories;
    final exp = expenditureCache[k]?.total;
    if (intake == null && exp == null) continue;
    rows.add(EnergyDayRow(
      date: k,
      intakeKcal: intake,
      expenditureKcal: exp,
      balanceKcal: (intake != null && exp != null) ? intake - exp : null,
    ));
  }

  return WeeklyEnergyStats(
    avgIntake: avgIntake,
    intakeDays: intakeDays.length,
    avgExpenditure: avgExpenditure,
    avgBalance: avgBalance,
    expectedKgPerWeek: expectedKgPerWeek,
    dayRows: rows,
  );
}
