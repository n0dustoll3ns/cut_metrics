/// Все настраиваемые константы Фазы 7 — в ОДНОМ месте.
///
/// Паттерн `RecommendationConfig` Фазы 5 («писать код так, чтобы это было
/// зафиксировано в одном месте», решение пользователя 2026-08-21): при
/// калибровке менять только этот файл. Источник значений — спека
/// `docs/phase7_nutrition_energy_spec.md` §0 (решения 2026-09-10/11) и A.3.
library;

/// Источник BMR для отображения в «Расходе калорий» (Фаза 7, B.4).
enum BmrSource { manual, healthConnect, mifflin, none }

/// Пол пользователя — для формулы Mifflin-St Jeor (A.2: `energy_sex` = m/f).
///
/// HC пол не хранит — ленивый ручной ввод (подсказка B.5 только когда BMR
/// не рассчитать ни одним способом).
enum EnergySex { male, female }

/// Интенсивность силовой сессии — Compendium of Physical Activities
/// (Ainsworth 2011): код 02050 (умеренная) = 3.5 MET, код 02060 (тяжёлая) =
/// 6.0 MET (A.2: `energy_training_intensity` = moderate/heavy).
enum TrainingIntensity { moderate, heavy }

/// Источник BMR (A.2: `energy_bmr_mode`).
enum BmrMode { auto, manual }

/// Профиль расхода — параметры модели из настроек (A.2) + ручные оверрайды
/// компонентов (§0 п. 5: у каждого компонента оверрайд поверх автокаскада).
///
/// Загружается/сохраняется целиком через `SettingsService` (префикс
/// `energy_`). [heightCm] — ТОЛЬКО ручной ввод: `null` = пользователь не
/// вводил, и VM подставляет префилл из HC `HEIGHT` (который может обновляться,
/// пока нет ручного значения).
class ExpenditureProfile {
  /// Пол; `null` — не указан (Mifflin недоступен).
  final EnergySex? sex;

  /// Год рождения; `null` — не указан. Возраст = год даты − birthYear (A.3).
  final int? birthYear;

  /// Рост, см — ручной ввод; `null` → префилл из HC `HEIGHT` в VM.
  final double? heightCm;

  /// Режим BMR: авто-каскад или ручная константа.
  final BmrMode bmrMode;

  /// Ручной BMR, ккал/день (действует при `bmrMode == manual`).
  final double? bmrManualKcal;

  /// Коэффициент шагов, ккал/кг/шаг (§0 п. 14: хранится коэффициент,
  /// UI оперирует «ккал на 1000 шагов» = коэффициент × вес × 1000).
  final double stepsKcalPerKgPerStep;

  /// Частота силовых, раз/нед (0–7; дефолт 0 — консервативно, §0 п. 11).
  final int trainingFreqPerWeek;

  /// Длительность силовой сессии, мин (дефолт 60, §0 п. 11).
  final int trainingDurationMin;

  /// Интенсивность силовой (дефолт «умеренная» 3.5 MET, §0 п. 11).
  final TrainingIntensity trainingIntensity;

  /// «Своя ккал/сессия» — оверрайд MET-расчёта; `null` = считать по MET.
  final double? trainingKcalPerSession;

  /// Бытовой расход, ккал/день (TEF + мелкая активность; дефолт 200).
  final double householdKcal;

  const ExpenditureProfile({
    this.sex,
    this.birthYear,
    this.heightCm,
    this.bmrMode = BmrMode.auto,
    this.bmrManualKcal,
    this.stepsKcalPerKgPerStep = ExpenditureConfig.defaultStepsKcalPerKgPerStep,
    this.trainingFreqPerWeek = 0,
    this.trainingDurationMin = 60,
    this.trainingIntensity = TrainingIntensity.moderate,
    this.trainingKcalPerSession,
    this.householdKcal = ExpenditureConfig.defaultHouseholdKcal,
  });

  /// Профиль полон для Mifflin: пол + год рождения + рост известны.
  bool get isCompleteForMifflin {
    final h = heightCm;
    return sex != null && birthYear != null && h != null && h > 0;
  }

  ExpenditureProfile copyWith({
    EnergySex? sex,
    bool clearSex = false,
    int? birthYear,
    bool clearBirthYear = false,
    double? heightCm,
    bool clearHeightCm = false,
    BmrMode? bmrMode,
    double? bmrManualKcal,
    bool clearBmrManualKcal = false,
    double? stepsKcalPerKgPerStep,
    int? trainingFreqPerWeek,
    int? trainingDurationMin,
    TrainingIntensity? trainingIntensity,
    double? trainingKcalPerSession,
    bool clearTrainingKcalPerSession = false,
    double? householdKcal,
  }) {
    return ExpenditureProfile(
      sex: clearSex ? null : (sex ?? this.sex),
      birthYear: clearBirthYear ? null : (birthYear ?? this.birthYear),
      heightCm: clearHeightCm ? null : (heightCm ?? this.heightCm),
      bmrMode: bmrMode ?? this.bmrMode,
      bmrManualKcal: clearBmrManualKcal ? null : (bmrManualKcal ?? this.bmrManualKcal),
      stepsKcalPerKgPerStep: stepsKcalPerKgPerStep ?? this.stepsKcalPerKgPerStep,
      trainingFreqPerWeek: trainingFreqPerWeek ?? this.trainingFreqPerWeek,
      trainingDurationMin: trainingDurationMin ?? this.trainingDurationMin,
      trainingIntensity: trainingIntensity ?? this.trainingIntensity,
      trainingKcalPerSession:
          clearTrainingKcalPerSession ? null : (trainingKcalPerSession ?? this.trainingKcalPerSession),
      householdKcal: householdKcal ?? this.householdKcal,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenditureProfile &&
          sex == other.sex &&
          birthYear == other.birthYear &&
          heightCm == other.heightCm &&
          bmrMode == other.bmrMode &&
          bmrManualKcal == other.bmrManualKcal &&
          stepsKcalPerKgPerStep == other.stepsKcalPerKgPerStep &&
          trainingFreqPerWeek == other.trainingFreqPerWeek &&
          trainingDurationMin == other.trainingDurationMin &&
          trainingIntensity == other.trainingIntensity &&
          trainingKcalPerSession == other.trainingKcalPerSession &&
          householdKcal == other.householdKcal;

  @override
  int get hashCode => Object.hash(
        sex,
        birthYear,
        heightCm,
        bmrMode,
        bmrManualKcal,
        stepsKcalPerKgPerStep,
        trainingFreqPerWeek,
        trainingDurationMin,
        trainingIntensity,
        trainingKcalPerSession,
        householdKcal,
      );

  @override
  String toString() =>
      'ExpenditureProfile(sex: $sex, birth: $birthYear, height: $heightCm, '
      'bmr: $bmrMode/${bmrManualKcal?.toStringAsFixed(0) ?? '—'}, '
      'шаги: $stepsKcalPerKgPerStep, силовые: $trainingFreqPerWeek×'
      '$trainingDurationMinмин/$trainingIntensity'
      '${trainingKcalPerSession != null ? '/своя ${trainingKcalPerSession!.toStringAsFixed(0)}' : ''}, '
      'быт: $householdKcal)';
}

/// Константы формул расхода/энергобаланса (A.3) и тексты v2 (C.2).
class ExpenditureConfig {
  ExpenditureConfig._();

  // ─── BMR: Mifflin-St Jeor ──────────────────────────────────────────────────

  static const double mifflinWeightCoef = 10;
  static const double mifflinHeightCoef = 6.25;
  static const double mifflinAgeCoef = 5;
  static const double mifflinMaleOffset = 5;
  static const double mifflinFemaleOffset = -161;

  // ─── Компоненты расхода ────────────────────────────────────────────────────

  /// Нетто-стоимость ходьбы: `шаги × вес × 0.0004` ккал (Margaria ≈ 0.45–0.5
  /// ккал/кг/км чистая стоимость). Нетто обязательно — BMR теперь отдельный
  /// компонент за полные сутки, gross давал бы задвоение ~100–150 ккал/день.
  /// Прежний gross-коэффициент 0.0005 был корректен, когда BMR не считался.
  static const double defaultStepsKcalPerKgPerStep = 0.0004;

  /// MET умеренной силовой (Compendium 02050).
  static const double trainingMetModerate = 3.5;

  /// MET тяжёлой силовой (Compendium 02060).
  static const double trainingMetHeavy = 6.0;

  /// Нетто-вычитание 1 MET (расход поверх обмена) — та же причина, что и у
  /// шагов: BMR уже учтён отдельным компонентом.
  static const double trainingNetMetSubtraction = 1.0;

  /// Бытовой расход, ккал/день: TEF (~10% рациона) + мелкая активность сверх
  /// учтённых шагов; литературный коридор для сидячих 150–300.
  static const double defaultHouseholdKcal = 200;

  /// Энергетический эквивалент 1 кг веса, ккал (7700 ккал/кг).
  static const double kcalPerKgFat = 7700;

  // ─── Целевой дефицит и дельта рекомендаций ─────────────────────────────────

  /// Целевой дефицит, ккал/день: `вес × темп(%) × 11` (7700 ккал/кг ÷ 7 дней
  /// ÷ 100). Пример: 70 кг × 0.8% → −616 ккал/день.
  static double targetDeficitKcalPerDay(double weightKg, double targetPacePercent) =>
      weightKg * targetPacePercent * kcalPerKgFat / 700;

  /// Ккал/день на 1 процентный пункт темпа на 1 кг веса (7700 ÷ 7 ÷ 100).
  static const double kcalPerPacePointPerKg = 11;

  /// Коридор дельты рекомендаций v2 (§0 п. 13), ккал/день.
  static const double minDeltaKcal = 50;
  static const double maxDeltaKcal = 300;

  /// Дельта рекомендаций v2 (§0 п. 13, 2026-09-11): динамическая —
  /// `вес × |целевой − фактический темп (п.п.)| × 11`, коридор 50–300
  /// ккал/день, округление до 10.
  static int recommendationDeltaKcal(double weightKg, double actualPacePercent, double targetPacePercent) {
    final raw = weightKg * (actualPacePercent - targetPacePercent).abs() * kcalPerPacePointPerKg;
    final clamped = raw.clamp(minDeltaKcal, maxDeltaKcal);
    return (clamped / 10).round() * 10;
  }

  // ─── Тексты v2 (C.2; подстановка {balance}/{actual}/{target}/{intake}/
  // ─── {intakeNew}/{delta} — движком при наличии WeeklyEnergyStats) ──────────

  /// v2, «в темпе» — с энергостатами.
  static const String recInPaceV2 =
      'Держишь дефицит {balance} ккал/день — темп {actual}%/нед в цели. '
      'Оставь рацион без изменений.';

  /// v2, слишком медленно: `{intakeNew} = {intake} − {delta}`.
  static const String recTooSlowV2 =
      'Темп {actual}%/нед ниже цели {target}%/нед. Средний приход {intake} '
      'ккал/день — снизь до {intakeNew} (−{delta} ккал).';

  /// v2, слишком быстро: `{intakeNew} = {intake} + {delta}`.
  static const String recTooFastV2 =
      'Темп {actual}%/нед выше цели {target}%/нед. Средний приход {intake} '
      'ккал/день — добавь до {intakeNew} (+{delta} ккал).';

  // ─── Диапазоны загрузки (спека §7) ─────────────────────────────────────────

  /// Окно предзагрузки NUTRITION/BASAL, дней (= maxTrendDays).
  static const int nutritionLoadDays = 90;

  /// Окно предзагрузки HEIGHT, дней (рост меняется медленно).
  static const int heightLoadDays = 365;
}
