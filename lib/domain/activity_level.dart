import 'package:cut_metrics/domain/recommendation_config.dart';

/// Уровень активности пользователя 1–5 — добавка расхода калорий на тренировки.
///
/// Коэффициент `kcalPerKgPerDay` нормализован по весу (MET·часы/день):
/// при 80 кг уровень 3 даёт +240 ккал/день. Дефолт — [level1] (консервативно,
/// не завышаем расход у нового пользователя).
///
/// Тексты и коэффициенты утверждены пользователем 2026-08-21 —
/// см. `docs/phase5_ui_screens_and_activity_spec.md` §2.2.
enum ActivityLevel {
  level1('Минимальная', 'Без тренировок', 0.0),
  level2('Лёгкая', '1–2 тренировки в неделю', 1.5),
  level3('Умеренная', '3–4 тренировки в неделю', 3.0),
  level4('Высокая', '5–6 тренировки в неделю', 4.5),
  level5('Очень высокая', 'Тренировки каждый день', 6.0);

  const ActivityLevel(this.title, this.description, this.kcalPerKgPerDay);

  /// Короткое название для списка в настройках.
  final String title;

  /// Пояснение для списка в настройках.
  final String description;

  /// Добавка расхода, ккал на 1 кг веса в день.
  final double kcalPerKgPerDay;

  /// Уровень по номеру 1–5 (для чтения из настроек). Неверный номер → [level1].
  static ActivityLevel byNumber(int number) {
    return values.any((l) => l.index + 1 == number)
        ? values.firstWhere((l) => l.index + 1 == number)
        : ActivityLevel.level1;
  }

  /// Номер уровня 1–5 (для записи в настройки).
  int get number => index + 1;
}

/// Ккал, потраченные на шаги: `шаги × вес × 0.0005`.
///
/// ≈400 ккал на 10 000 шагов при 80 кг.
double stepsToKcal(int steps, double weightKg) =>
    steps * weightKg * RecommendationConfig.stepsKcalPerKgPerStep;

/// Добавка расхода на тренировки для уровня: `kcalPerKgPerDay × вес`.
double trainingKcal(ActivityLevel level, double weightKg) =>
    level.kcalPerKgPerDay * weightKg;

/// Суммарный расход калорий за день: шаги + тренировки.
///
/// День без записи шагов — 0 шагов (добавка уровня начисляется всегда).
double dailyCaloriesBurned({
  required int steps,
  required double weightKg,
  required ActivityLevel level,
}) =>
    stepsToKcal(steps, weightKg) + trainingKcal(level, weightKg);
