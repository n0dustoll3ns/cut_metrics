import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';

/// Расход калорий за день — 4 компонента (Фаза 7, A.5; решения §0 пп. 1, 3, 5).
///
/// Считается синхронно в `HealthDataProcessor.computeExpenditures` из
/// резолвленных кешей (вес/шаги/BASAL/профиль) — сырые точки не хранятся.
/// День без BMR (каскад A.4 вернул null) не получает `ExpenditureDay` вовсе —
/// баланс за такой день не считается.
class ExpenditureDay {
  final DateKey date;

  /// Базальный метаболизм, ккал/день — каскад: ручной оверрайд →
  /// HC `BASAL_ENERGY_BURNED` (last-wins за день) → Mifflin-St Jeor.
  final double bmrKcal;

  /// Шаги: `шаги_дня × вес_на_дату × коэффициент` (нетто, дефолт 0.0004).
  final double stepsKcal;

  /// Силовые: `(MET − 1) × вес × часы × частота / 7` (или своя ккал/сессия ×
  /// частота / 7), Compendium 3.5/6.0 MET.
  final double trainingKcal;

  /// Бытовой расход (TEF + мелкая активность), дефолт 200 ккал/день.
  final double householdKcal;

  const ExpenditureDay({
    required this.date,
    required this.bmrKcal,
    required this.stepsKcal,
    required this.trainingKcal,
    required this.householdKcal,
  });

  double get total => bmrKcal + stepsKcal + trainingKcal + householdKcal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenditureDay &&
          date == other.date &&
          bmrKcal == other.bmrKcal &&
          stepsKcal == other.stepsKcal &&
          trainingKcal == other.trainingKcal &&
          householdKcal == other.householdKcal;

  @override
  int get hashCode => Object.hash(date, bmrKcal, stepsKcal, trainingKcal, householdKcal);

  @override
  String toString() =>
      'ExpenditureDay(date: $date, bmr: ${bmrKcal.toStringAsFixed(0)}, '
      'шаги: ${stepsKcal.toStringAsFixed(0)}, силовые: ${trainingKcal.toStringAsFixed(0)}, '
      'быт: ${householdKcal.toStringAsFixed(0)}, всего: ${total.toStringAsFixed(0)})';
}

/// Энергобаланс одного дня: приход ([intake]) против расхода ([out]).
///
/// Создаётся только для дней, где есть И питание, И расход — иначе баланс
/// не определён (A.4 п.4) и день не попадает в график/средние баланса.
class EnergyBalanceDay {
  final NutritionDay intake;
  final ExpenditureDay out;

  const EnergyBalanceDay({required this.intake, required this.out});

  DateKey get date => intake.date;

  /// Чистый баланс: приход − расход. Отрицательный = дефицит.
  double get balance => intake.calories - out.total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EnergyBalanceDay && intake == other.intake && out == other.out;

  @override
  int get hashCode => Object.hash(intake, out);

  @override
  String toString() =>
      'EnergyBalanceDay($date, приход: ${intake.calories.toStringAsFixed(0)}, '
      'расход: ${out.total.toStringAsFixed(0)}, баланс: ${balance.toStringAsFixed(0)})';
}

/// Вычисляет BMR по формуле Mifflin-St Jeor (A.3).
///
/// М: `10W + 6.25H − 5A + 5`; Ж: `10W + 6.25H − 5A − 161`
/// (W — кг, H — см, A — полных лет). Стандарт первого выбора ADA
/// (Frankenfield et al. 2005), когда состав тела неизвестен.
double mifflinStJeor({
  required EnergySex sex,
  required double weightKg,
  required double heightCm,
  required int ageYears,
}) {
  final base = ExpenditureConfig.mifflinWeightCoef * weightKg +
      ExpenditureConfig.mifflinHeightCoef * heightCm -
      ExpenditureConfig.mifflinAgeCoef * ageYears;
  return sex == EnergySex.male
      ? base + ExpenditureConfig.mifflinMaleOffset
      : base + ExpenditureConfig.mifflinFemaleOffset;
}
