import 'package:cut_metrics/domain/calc_trace.dart';
import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/domain/gap_rule.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/recommendation_engine.dart';
import 'package:cut_metrics/domain/sleep_day.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/domain/weekly_energy_stats.dart';
import 'package:cut_metrics/ui/format.dart';
import 'package:health/health.dart';

/// Билдеры трасс «Как рассчитано» (CalcDetail, `docs/calc_detail_implementation_task.md` §3).
///
/// Чистые функции: принимают кеши VM / сырые точки сессии / настройки и
/// возвращают готовый [CalcTrace]. ГЛАВНОЕ ОГРАНИЧЕНИЕ: формулы и правила не
/// меняются и не дублируются — победители и значения читаются из результатов
/// существующих функций домена (`resolve*`, `computeEma`, `computeEnergyStats`,
/// `RecommendationEngine`), здесь только объяснение с подстановкой чисел.
/// Промежуточные значения для подстановок пересчитываются ТЕМИ ЖЕ формулами —
/// равенство итога трассы числу на экране фиксируется регрессионными тестами.
///
/// Форматирование — по правилам экранов (§2 ТЗ): шаги/ккал — `format.dart`
/// (разделители разрядов), вес — 1 знак, дельта — округление до 10,
/// промежуточные значения — 1 знак после запятой.

/// Компонент расхода за день — для `expenditureComponentTrace` (строки
/// «Настроек» расхода, B.4).
enum ExpenditureComponent { bmr, steps, training, household }

/// Результат `avgWithTrace`-функций (§3.5): значение для геттера VM (публичный
/// API не меняется) + трасса для листа.
class AvgWithTrace<T> {
  final T? value;
  final CalcTrace trace;

  const AvgWithTrace(this.value, this.trace);
}

/// Результат [avgMacrosWithTrace]: три средних по одним и тем же дням.
class AvgMacrosWithTrace {
  final double? protein;
  final double? fat;
  final double? carbs;
  final CalcTrace trace;

  const AvgMacrosWithTrace({this.protein, this.fat, this.carbs, required this.trace});
}

// ─── Приватные хелперы форматирования ────────────────────────────────────────

const List<String> _monthsFull = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// «22 сентября» — подписи дат в трассах.
String _d(DateKey k) => '${k.value.day} ${_monthsFull[k.value.month - 1]}';

/// 1 знак после запятой (вес, промежуточные значения).
String _fmt1(double v) => v.toStringAsFixed(1);

/// Ккал «как есть» (паттерн движка `_formatKcal`): целое — целым,
/// дробное — 1 знак.
String _fmtKcal(double v) {
  final r = v.roundToDouble();
  return v == r ? r.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Число со знаком «−»/«+», 1 знак (изменение веса, кг/нед).
String _signed1(double v) => v == 0
    ? '0'
    : v < 0
        ? '−${v.abs().toStringAsFixed(1)}'
        : '+${v.toStringAsFixed(1)}';

/// Число со знаком, 2 знака (ожидаемый кг/нед — формат Саммари).
String _signed2(double v) => v == 0
    ? '0.00'
    : v < 0
        ? '−${v.abs().toStringAsFixed(2)}'
        : '+${v.abs().toStringAsFixed(2)}';

/// Причины, почему источник-конкурент не попал в расчёт (язык макетов).
const String _kReasonLowerSum = 'сумма меньше';
const String _kReasonFewerDays = 'меньше покрытие дней';
const String _kReasonRefused = 'источник отклонён';
const String _kReasonLostAuto = 'проиграл авто-правилу';
const String _kReasonManualWins = 'ручная запись побеждает';
const String _kReasonOtherChosen = 'выбран другой источник';

/// Калории записи питания точки (безопасно, `null` — не питание).
double? _kcalOf(HealthDataPoint p) =>
    (p.value as NutritionHealthValue).calories;

/// Целочисленное значение точки (шаги/вес/рост).
int _intOf(HealthDataPoint p) =>
    (p.value as NumericHealthValue).numericValue.toInt();

/// Строки цепочки EMA «дата · сырой вес · EMA» с флагами рестартов
/// (разрыв [RecommendationConfig.emaBreakGapDays]+ пустых дней — правило то
/// же, что в `HealthDataProcessor.computeEma`).
List<TraceEmaRow> _emaRows(
  Map<DateKey, WeightDay> weightCache,
  Map<DateKey, WeightDay> emaCache,
) {
  final sorted = emaCache.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  final result = <TraceEmaRow>[];
  DateKey? prevWeightDate;
  for (final e in sorted) {
    final raw = weightCache[e.date]?.weight;
    var restart = false;
    if (prevWeightDate != null) {
      final gap = e.date.value.difference(prevWeightDate.value).inDays - 1;
      restart = gap >= RecommendationConfig.emaBreakGapDays;
    }
    result.add(TraceEmaRow(
      dateText: _d(e.date),
      rawWeight: raw ?? e.weight,
      ema: e.weight,
      seriesRestart: restart,
    ));
    prevWeightDate = e.date;
  }
  return result;
}

// ─── §3.1 Шаги за день ───────────────────────────────────────────────────────

/// Трасса карточки «Шаги» за дату: правило «один источник на день», сумма
/// записей победителя, конкуренты с причинами.
CalcTrace stepsDayTrace({
  required HealthDataProcessor processor,
  required DateKey date,
  required StepsDay? day,
  required List<HealthDataPoint> rawStepsPoints,
  required Map<String, ConfirmDecision> decisions,
  required SourceSelection selection,
}) {
  final dateText = _d(date);
  final sums = processor.stepsSumsBySource(date, rawStepsPoints);
  final dayPoints =
      rawStepsPoints.where((p) => DateKey(p.dateFrom) == date).toList();

  String recordsOf(String source) => dayPoints
      .where((p) => HealthDataProcessor.sourcePackageOf(p) == source)
      .map(_intOf)
      .map(formatThousands)
      .join(' + ');

  final winner = day?.sourcePackage;
  final inputs = <TraceInput>[];
  final steps = <TraceStep>[];

  if (day == null) {
    // Данных нет: трасса-объяснение, без расчёта.
    for (final source in sums.keys) {
      inputs.add(TraceInput(
        label: 'Шаги за $dateText — $source',
        valueText: formatThousands(sums[source] ?? 0),
        kind: TraceSourceKind.healthConnect,
        sourceName: source,
        notUsed: true,
        notUsedReason: decisions[source] == ConfirmDecision.refused
            ? _kReasonRefused
            : 'пригодных записей нет',
      ));
    }
    steps.add(const TraceStep(
      title: 'Пригодных записей за день нет',
      resultText: '→ день без данных шагов',
      note: 'все внешние источники отклонены или сумм нет — '
          'резолюция вернула null',
    ));
    return CalcTrace(
      title: 'Шаги',
      subtitle: dateText,
      inputs: inputs,
      steps: steps,
      resultText: '—',
      resultUnit: 'шагов',
    );
  }

  // Победитель.
  final isManual = day.source == DataSource.manual;
  inputs.add(TraceInput(
    label: 'Шаги за $dateText — ${isManual ? 'ручная запись' : winner}',
    valueText: formatThousands(day.steps),
    kind: isManual ? TraceSourceKind.manual : TraceSourceKind.healthConnect,
    sourceName: winner,
    recordsText: recordsOf(winner ?? ''),
  ));

  // Конкуренты: прочие источники дня.
  final competitors = sums.keys.where((s) => s != winner).toList()
    ..sort((a, b) => (sums[b] ?? 0).compareTo(sums[a] ?? 0));
  for (final source in competitors) {
    inputs.add(TraceInput(
      label: 'Шаги за $dateText — $source',
      valueText: formatThousands(sums[source] ?? 0),
      kind: TraceSourceKind.healthConnect,
      sourceName: source,
      recordsText: recordsOf(source),
      notUsed: true,
      notUsedReason:
          _stepsReason(source, day.source == DataSource.manual, day.steps, sums, decisions, selection),
    ));
  }

  // Шаг 1: правило «один источник на день».
  if (isManual) {
    steps.add(const TraceStep(
      title: 'Правило «один источник на день»: Tier 1 → выбранный источник → «Авто»',
      resultText: 'победила ручная запись (Tier 1) — ручной ввод всегда побеждает',
    ));
  } else if (!selection.isAuto) {
    steps.add(TraceStep(
      title: 'Правило «один источник на день»: Tier 1 → выбранный источник → «Авто»',
      formulaText: 'источник: ${selection.package}',
      resultText: 'взят выбранный источник ($winner)',
    ));
  } else if (competitors.isEmpty) {
    steps.add(TraceStep(
      title: 'Правило «один источник на день»: Tier 1 → выбранный источник → «Авто»',
      resultText: 'источник один — $winner',
    ));
  } else {
    final best = sums[competitors.first] ?? 0;
    steps.add(TraceStep(
      title: 'Правило «один источник на день»: Tier 1 → выбранный источник → «Авто»',
      formulaText: '${formatThousands(day.steps)} > ${formatThousands(best)}',
      resultText: '→ $winner (максимальная сумма за день)',
    ));
  }

  // Шаг 2: сумма записей победителя.
  steps.add(TraceStep(
    title: 'Суммируем записи победившего источника',
    formulaText: recordsOf(winner ?? ''),
    resultText: '= ${formatThousands(day.steps)}',
    note: 'агрегат Health Connect не используется — '
        'резолюция по сырым точкам (Фаза 6 A2)',
  ));

  return CalcTrace(
    title: 'Шаги',
    subtitle: dateText,
    inputs: inputs,
    steps: steps,
    resultText: formatThousands(day.steps),
    resultUnit: 'шагов',
  );
}

/// Причина исключения источника-конкурента из резолюции шагов.
String _stepsReason(
  String source,
  bool manualWins,
  int winnerSum,
  Map<String, int> sums,
  Map<String, ConfirmDecision> decisions,
  SourceSelection selection,
) {
  if (decisions[source] == ConfirmDecision.refused) return _kReasonRefused;
  if (manualWins) return _kReasonManualWins;
  if (!selection.isAuto) return _kReasonOtherChosen;
  final s = sums[source] ?? 0;
  if (s < winnerSum) return _kReasonLowerSum;
  return _kReasonLostAuto; // равная сумма — победил первый по порядку обхода
}


// ─── §3.2 Питание за день (калории) ──────────────────────────────────────────

/// Трасса калорий за дату: авто-правило по покрытию дней, Tier 1 «Итог дня»,
/// сумма калорий победителя.
CalcTrace nutritionDayTrace({
  required HealthDataProcessor processor,
  required DateKey date,
  required NutritionDay? day,
  required List<HealthDataPoint> rawNutritionPoints,
  required Map<String, ConfirmDecision> decisions,
  required SourceSelection selection,
}) {
  final dateText = _d(date);
  final stats = processor.nutritionSourceStats(rawNutritionPoints);
  final daySources = rawNutritionPoints
      .where((p) => DateKey(p.dateFrom) == date)
      .map(HealthDataProcessor.sourcePackageOf)
      .toSet();
  final winner = day?.sourcePackage;
  final isManual = day?.source == DataSource.manual;

  String recordsOf(String source) => rawNutritionPoints
      .where((p) => DateKey(p.dateFrom) == date && HealthDataProcessor.sourcePackageOf(p) == source)
      .map((p) => _kcalOf(p))
      .whereType<double>()
      .map(formatThousands)
      .join(' + ');

  final inputs = <TraceInput>[];
  final steps = <TraceStep>[];

  if (day == null) {
    for (final source in daySources) {
      inputs.add(TraceInput(
        label: 'Калории за $dateText — $source',
        valueText: formatThousands(stats[source]?.kcalSum ?? 0),
        kind: TraceSourceKind.healthConnect,
        sourceName: source,
        notUsed: true,
        notUsedReason: decisions[source] == ConfirmDecision.refused
            ? _kReasonRefused
            : 'пригодных записей нет',
      ));
    }
    steps.add(const TraceStep(
      title: 'Пригодных записей за день нет',
      resultText: '→ день без данных питания («нет данных ≠ 0»)',
    ));
    return CalcTrace(
      title: 'Питание',
      subtitle: dateText,
      inputs: inputs,
      steps: steps,
      resultText: '—',
      resultUnit: 'ккал',
    );
  }

  // Победитель + его записи за день.
  inputs.add(TraceInput(
    label: 'Калории за $dateText — ${isManual ? 'Итог дня' : winner}',
    valueText: formatThousands(day.calories),
    kind: isManual ? TraceSourceKind.manual : TraceSourceKind.healthConnect,
    sourceName: winner,
    recordsText: recordsOf(winner ?? ''),
  ));

  // Конкуренты: прочие источники дня.
  for (final source in daySources.where((s) => s != winner)) {
    inputs.add(TraceInput(
      label: 'Калории за $dateText — $source',
      valueText: formatThousands(stats[source]?.kcalSum ?? 0),
      kind: TraceSourceKind.healthConnect,
      sourceName: source,
      note: 'покрытие: ${stats[source]?.days ?? 0} дн. диапазона',
      notUsed: true,
      notUsedReason: _nutritionReason(source, isManual, decisions, selection),
    ));
  }

  // Шаг 1: авто-правило по покрытию дней (среди внешних источников).
  final externals = stats.values
      .where((s) => s.package != processor.appPackageId)
      .toList()
    ..sort((a, b) => b.days.compareTo(a.days));
  if (externals.length > 1) {
    steps.add(TraceStep(
      title: 'Авто-правило источника питания: наибольшее покрытие дней диапазона',
      formulaText: externals.map((s) => '${s.package} — ${s.days} дн.').join(', '),
      resultText: '→ ${externals.first.package}',
      note: 'НЕ максимальная сумма; при равенстве покрытия — больше записей, '
          'затем большая сумма калорий',
    ));
  } else if (externals.length == 1) {
    steps.add(TraceStep(
      title: 'Авто-правило источника питания: наибольшее покрытие дней диапазона',
      resultText: 'внешний источник один — ${externals.first.package}',
    ));
  } else {
    steps.add(const TraceStep(
      title: 'Авто-правило источника питания: наибольшее покрытие дней диапазона',
      resultText: 'внешних источников нет',
    ));
  }

  // Шаг 2: приоритет Tier 1 / выбранного источника.
  if (isManual) {
    steps.add(const TraceStep(
      title: 'Ручной «Итог дня» (Tier 1) побеждает для своей даты',
      resultText: 'взят итог дня, записанный вручную',
    ));
  } else if (!selection.isAuto) {
    steps.add(TraceStep(
      title: 'Выбранный источник',
      formulaText: 'источник: ${selection.package}',
      resultText: 'суммируем только его записи за день',
    ));
  }

  // Шаг 3: сумма калорий победителя.
  steps.add(TraceStep(
    title: 'Суммируем калории записей победившего источника',
    formulaText: recordsOf(winner ?? ''),
    resultText: '= ${formatThousands(day.calories)}',
    note: 'макросы — сумма по записям, где они есть; '
        'день без записей победителя = «нет данных» (нет данных ≠ 0)',
  ));

  final macros = (day.protein != null || day.fat != null || day.carbs != null)
      ? '${day.protein?.round() ?? '—'} / ${day.fat?.round() ?? '—'} / '
          '${day.carbs?.round() ?? '—'} г (Б/Ж/У)'
      : null;

  return CalcTrace(
    title: 'Питание',
    subtitle: dateText,
    inputs: inputs,
    steps: steps,
    resultText: formatThousands(day.calories),
    resultUnit: 'ккал',
    resultNote: macros,
  );
}

/// Причина исключения источника-конкурента из резолюции питания.
String _nutritionReason(
  String source,
  bool manualWins,
  Map<String, ConfirmDecision> decisions,
  SourceSelection selection,
) {
  if (decisions[source] == ConfirmDecision.refused) return _kReasonRefused;
  if (manualWins) return _kReasonManualWins;
  if (!selection.isAuto) return _kReasonOtherChosen;
  return _kReasonFewerDays;
}


// ─── §3.3 Расход за день: 4 компонента ───────────────────────────────────────

/// Полная трасса расхода за день (4 компонента + сумма).
CalcTrace expenditureDayTrace({
  required HealthDataProcessor processor,
  required DateKey date,
  required ExpenditureDay? day,
  required Map<DateKey, WeightDay> weightCache,
  required Map<DateKey, StepsDay> stepsCache,
  required Map<DateKey, double> basalCache,
  required ExpenditureProfile profile,
  double? hcHeightCm,
}) {
  return _expenditureTrace(
    processor: processor,
    date: date,
    day: day,
    weightCache: weightCache,
    stepsCache: stepsCache,
    basalCache: basalCache,
    profile: profile,
    hcHeightCm: hcHeightCm,
    only: null,
  );
}

/// Трасса ОДНОГО компонента расхода — для строк «Настроек» (B.4).
CalcTrace expenditureComponentTrace({
  required HealthDataProcessor processor,
  required DateKey date,
  required ExpenditureDay? day,
  required Map<DateKey, WeightDay> weightCache,
  required Map<DateKey, StepsDay> stepsCache,
  required Map<DateKey, double> basalCache,
  required ExpenditureProfile profile,
  double? hcHeightCm,
  required ExpenditureComponent component,
}) {
  return _expenditureTrace(
    processor: processor,
    date: date,
    day: day,
    weightCache: weightCache,
    stepsCache: stepsCache,
    basalCache: basalCache,
    profile: profile,
    hcHeightCm: hcHeightCm,
    only: component,
  );
}

CalcTrace _expenditureTrace({
  required HealthDataProcessor processor,
  required DateKey date,
  required ExpenditureDay? day,
  required Map<DateKey, WeightDay> weightCache,
  required Map<DateKey, StepsDay> stepsCache,
  required Map<DateKey, double> basalCache,
  required ExpenditureProfile profile,
  double? hcHeightCm,
  required ExpenditureComponent? only,
}) {
  final dateText = _d(date);

  // Эффективный рост — то же правило, что в VM `_refreshExpenditure`:
  // ручной ввод побеждает, иначе HC-префилл.
  final heightFromHc = profile.heightCm == null;
  final effectiveHeight = profile.heightCm ?? hcHeightCm;

  final weight = HealthDataProcessor.weightOnDate(weightCache, date);
  final weightLabel = (weight == null || weight.date == date)
      ? 'Вес на $dateText'
      : 'Вес на $dateText (запись от ${_d(weight.date)})';
  final stepsDay = stepsCache[date];
  final basal = basalCache[date];

  final inputs = <TraceInput>[];
  final steps = <TraceStep>[];

  final needBmr = only == null || only == ExpenditureComponent.bmr;
  final needSteps = only == null || only == ExpenditureComponent.steps;
  final needTraining = only == null || only == ExpenditureComponent.training;
  final needHousehold = only == null || only == ExpenditureComponent.household;

  // ── Входы ──
  if (needBmr) {
    if (profile.bmrMode == BmrMode.manual &&
        profile.bmrManualKcal != null &&
        profile.bmrManualKcal! > 0) {
      inputs.add(TraceInput(
        label: 'Ручной BMR',
        valueText: '${formatThousands(profile.bmrManualKcal!)} ккал/день',
        kind: TraceSourceKind.settings,
      ));
    } else if (basal != null && basal > 0) {
      inputs.add(TraceInput(
        label: 'HC BASAL за $dateText',
        valueText: '${formatThousands(basal)} ккал/день',
        kind: TraceSourceKind.healthConnect,
      ));
    }
  }
  if (needSteps) {
    inputs.add(TraceInput(
      label: weightLabel,
      valueText: weight == null ? '—' : '${_fmt1(weight.weight)} кг',
      kind: weight?.source == DataSource.manual
          ? TraceSourceKind.manual
          : TraceSourceKind.healthConnect,
      sourceName: weight?.sourcePackage,
      note: weight == null ? 'нет записи веса ≤ даты' : null,
    ));
    inputs.add(TraceInput(
      label: 'Шаги за $dateText',
      valueText: stepsDay == null ? '0' : formatThousands(stepsDay.steps),
      kind: stepsDay?.source == DataSource.manual
          ? TraceSourceKind.manual
          : TraceSourceKind.healthConnect,
      sourceName: stepsDay?.sourcePackage,
      note: stepsDay == null ? 'день без записи шагов = 0 шагов' : null,
    ));
    inputs.add(TraceInput(
      label: 'Коэффициент шагов',
      valueText: '${profile.stepsKcalPerKgPerStep} ккал/кг/шаг',
      kind: TraceSourceKind.settings,
    ));
  }
  if (needTraining) {
    inputs.add(TraceInput(
      label: 'Частота силовых',
      valueText: '${profile.trainingFreqPerWeek} р/нед',
      kind: TraceSourceKind.settings,
    ));
    final own = profile.trainingKcalPerSession;
    if (own != null && own > 0) {
      inputs.add(TraceInput(
        label: 'Своя ккал/сессия',
        valueText: '${formatThousands(own)} ккал',
        kind: TraceSourceKind.settings,
      ));
    } else {
      inputs.add(TraceInput(
        label: 'Длительность сессии',
        valueText: '${profile.trainingDurationMin} мин',
        kind: TraceSourceKind.settings,
      ));
      inputs.add(TraceInput(
        label: 'Интенсивность',
        valueText: profile.trainingIntensity == TrainingIntensity.moderate
            ? 'умеренная (3.5 MET)'
            : 'тяжёлая (6.0 MET)',
        kind: TraceSourceKind.settings,
      ));
    }
  }
  if (needHousehold) {
    inputs.add(TraceInput(
      label: 'Бытовой расход',
      valueText: '${formatThousands(profile.householdKcal)} ккал/день',
      kind: TraceSourceKind.settings,
    ));
  }


  // ── Шаги расчёта ──
  if (needBmr) {
    steps.add(_bmrCascadeStep(date,
        basal: basal,
        profile: profile,
        heightCm: effectiveHeight,
        heightFromHc: heightFromHc,
        weight: weight));
  }
  if (needSteps) {
    steps.add(_stepsKcalStep(stepsDay, weight, profile));
  }
  if (needTraining) {
    steps.add(_trainingKcalStep(profile, weight));
  }
  if (needHousehold) {
    steps.add(TraceStep(
      title: 'Бытовой расход (TEF + мелкая активность)',
      resultText: '= ${formatThousands(profile.householdKcal)}',
      note: 'константа профиля (настройки «Расход калорий»)',
    ));
  }

  // ── Итог ──
  if (only != null) {
    final value = switch (only) {
      ExpenditureComponent.bmr => day?.bmrKcal,
      ExpenditureComponent.steps => day?.stepsKcal,
      ExpenditureComponent.training => day?.trainingKcal,
      ExpenditureComponent.household => day?.householdKcal,
    };
    final label = switch (only) {
      ExpenditureComponent.bmr => 'Базальный (BMR)',
      ExpenditureComponent.steps => 'Шаги',
      ExpenditureComponent.training => 'Силовые',
      ExpenditureComponent.household => 'Бытовой',
    };
    return CalcTrace(
      title: 'Расход: $label',
      subtitle: dateText,
      inputs: inputs,
      steps: steps,
      resultText: value == null ? '—' : '≈ ${formatThousands(value)}',
      resultUnit: 'ккал/день',
      resultNote:
          value == null ? 'компонент не рассчитан — BMR недоступен' : null,
    );
  }

  if (day == null) {
    return CalcTrace(
      title: 'Расход калорий',
      subtitle: dateText,
      inputs: inputs,
      steps: steps,
      resultText: '—',
      resultUnit: 'ккал/день',
      resultNote: 'BMR не рассчитан ни одним способом — '
          'расход и баланс за день не считаются',
    );
  }

  steps.add(TraceStep(
    title: 'Сумма компонентов: BMR + шаги + силовые + бытовой',
    formulaText:
        '${formatThousands(day.bmrKcal)} + ${_fmtKcal(day.stepsKcal)} + '
        '${_fmtKcal(day.trainingKcal)} + ${formatThousands(day.householdKcal)}',
    resultText: '= ${formatThousands(day.total)}',
  ));

  return CalcTrace(
    title: 'Расход калорий',
    subtitle: dateText,
    inputs: inputs,
    steps: steps,
    resultText: '≈ ${formatThousands(day.total)}',
    resultUnit: 'ккал/день',
  );
}

/// Шаг каскада BMR: ручной → HC BASAL → Mifflin-St Jeor (с подстановкой
/// уровня, на котором остановились; если ни один не сработал — объяснение).
TraceStep _bmrCascadeStep(
  DateKey date, {
  required double? basal,
  required ExpenditureProfile profile,
  required double? heightCm,
  required bool heightFromHc,
  required WeightDay? weight,
}) {
  if (profile.bmrMode == BmrMode.manual &&
      profile.bmrManualKcal != null &&
      profile.bmrManualKcal! > 0) {
    return TraceStep(
      title: 'Каскад BMR: ручной → Health Connect → Mifflin-St Jeor',
      formulaText: 'ручной оверрайд',
      resultText: '${formatThousands(profile.bmrManualKcal!)} ✓',
    );
  }
  if (basal != null && basal > 0) {
    return TraceStep(
      title: 'Каскад BMR: ручной → Health Connect → Mifflin-St Jeor',
      formulaText:
          'ручной: не задан → HC BASAL за день: ${formatThousands(basal)}',
      resultText: '${formatThousands(basal)} ✓',
    );
  }

  // Mifflin: подстановка формулы или объяснение, почему не рассчитан.
  final missing = <String>[
    if (profile.sex == null) 'пол',
    if (profile.birthYear == null) 'год рождения',
    if (heightCm == null) 'рост',
  ];
  final heightNote = heightCm == null
      ? null
      : 'рост: ${formatThousands(heightCm)} см '
          '(${heightFromHc ? 'HC-префилл' : 'ручной ввод'}); '
          'возраст = год даты − год рождения';
  if (missing.isNotEmpty) {
    return TraceStep(
      title: 'Каскад BMR: ручной → Health Connect → Mifflin-St Jeor',
      formulaText: 'ручной: не задан → HC BASAL за день: нет',
      resultText: 'Mifflin: профиль неполон — нет ${missing.join(', ')}',
      note: 'BMR не рассчитан — заполните профиль в настройках «Расход калорий»',
    );
  }
  if (weight == null || weight.weight <= 0) {
    return TraceStep(
      title: 'Каскад BMR: ручной → Health Connect → Mifflin-St Jeor',
      formulaText: 'ручной: не задан → HC BASAL за день: нет',
      resultText: 'Mifflin: нет веса на дату — BMR не рассчитан',
      note: heightNote,
    );
  }

  final age = date.value.year - profile.birthYear!;
  final offset = profile.sex == EnergySex.male
      ? ExpenditureConfig.mifflinMaleOffset
      : ExpenditureConfig.mifflinFemaleOffset;
  final bmr = mifflinStJeor(
    sex: profile.sex!,
    weightKg: weight.weight,
    heightCm: heightCm!,
    ageYears: age,
  );
  final sign = offset < 0 ? '− ${offset.abs()}' : '+ $offset';
  return TraceStep(
    title: 'Каскад BMR: ручной → Health Connect → Mifflin-St Jeor',
    formulaText: 'ручной: не задан → HC BASAL за день: нет → Mifflin: '
        '${ExpenditureConfig.mifflinWeightCoef}×${_fmt1(weight.weight)} + '
        '${ExpenditureConfig.mifflinHeightCoef}×${formatThousands(heightCm)} − '
        '${ExpenditureConfig.mifflinAgeCoef}×$age $sign',
    resultText: '= ${formatThousands(bmr)} ✓',
    note: heightNote,
  );
}


/// Шаг «шаги»: `шаги_дня × вес_на_дату × коэффициент` с подстановкой.
TraceStep _stepsKcalStep(
    StepsDay? stepsDay, WeightDay? weight, ExpenditureProfile profile) {
  final steps = stepsDay?.steps ?? 0;
  if (weight == null) {
    return TraceStep(
      title: 'Шаги: шаги_дня × вес_на_дату × коэффициент',
      formulaText:
          '${formatThousands(steps)} × ${profile.stepsKcalPerKgPerStep}',
      resultText: 'нет веса на дату → компонент 0',
      note: 'день без записи шагов = 0 шагов',
    );
  }
  final kcal = steps * weight.weight * profile.stepsKcalPerKgPerStep;
  return TraceStep(
    title: 'Шаги: шаги_дня × вес_на_дату × коэффициент',
    formulaText: '${formatThousands(steps)} × ${_fmt1(weight.weight)} × '
        '${profile.stepsKcalPerKgPerStep}',
    resultText: '= ${_fmtKcal(kcal)}',
    note: steps == 0 ? 'день без записи шагов = 0 шагов' : null,
  );
}

/// Шаг «силовые»: своя ккал/сессия ЛИБО MET-расчёт, с подстановкой.
TraceStep _trainingKcalStep(ExpenditureProfile profile, WeightDay? weight) {
  final freq = profile.trainingFreqPerWeek;
  if (freq <= 0) {
    return const TraceStep(
      title: 'Силовые',
      resultText: 'частота 0 → 0',
    );
  }
  final own = profile.trainingKcalPerSession;
  if (own != null && own > 0) {
    return TraceStep(
      title: 'Силовые: своя ккал/сессия × частота / 7',
      formulaText: '${formatThousands(own)} × $freq / 7',
      resultText: '= ${_fmtKcal(own * freq / 7)}',
    );
  }
  final met = profile.trainingIntensity == TrainingIntensity.moderate
      ? ExpenditureConfig.trainingMetModerate
      : ExpenditureConfig.trainingMetHeavy;
  if (weight == null || weight.weight <= 0) {
    return TraceStep(
      title: 'Силовые: (MET − 1) × вес × часы × частота / 7',
      formulaText: '($met − 1) × ${profile.trainingDurationMin} мин × $freq / 7',
      resultText: 'нет веса на дату → компонент 0',
    );
  }
  final hours = profile.trainingDurationMin / 60;
  final kcal = (met - ExpenditureConfig.trainingNetMetSubtraction) *
      weight.weight *
      hours *
      freq /
      7;
  return TraceStep(
    title: 'Силовые: (MET − 1) × вес × часы × частота / 7',
    formulaText: '($met − 1) × ${_fmt1(weight.weight)} × '
        '${_fmtKcal(hours)} ч × $freq / 7',
    resultText: '= ${_fmtKcal(kcal)}',
    note: 'MET $met — Compendium (${profile.trainingIntensity.name}); '
        'нетто: −1 MET поверх обмена',
  );
}

// ─── §3.4 Баланс дня ─────────────────────────────────────────────────────────

/// Трасса энергобаланса дня: приход − расход + целевая линия графика.
CalcTrace balanceDayTrace({
  required DateKey date,
  required NutritionDay? intake,
  required ExpenditureDay? out,
  required WeightDay? latestWeight,
  required double targetPacePercent,
}) {
  final dateText = _d(date);
  final inputs = <TraceInput>[
    TraceInput(
      label: 'Приход за $dateText',
      valueText: intake == null ? '—' : formatThousands(intake.calories),
      kind: intake?.source == DataSource.manual
          ? TraceSourceKind.manual
          : TraceSourceKind.healthConnect,
      sourceName: intake?.sourcePackage,
      note: 'см. трассу калорий',
    ),
    TraceInput(
      label: 'Расход за $dateText',
      valueText: out == null ? '—' : '≈ ${formatThousands(out.total)}',
      kind: TraceSourceKind.computed,
      note: 'см. трассу расхода',
    ),
  ];

  final steps = <TraceStep>[];
  String resultText = '—';
  if (out == null || intake == null) {
    steps.add(TraceStep(
      title: 'Баланс = приход − расход',
      resultText: 'баланс не считается',
      note: out == null
          ? 'расход не рассчитан: BMR недоступен (A.4 п.4)'
          : 'дня нет в данных питания («нет данных ≠ 0»)',
    ));
  } else {
    final balance = intake.calories - out.total;
    steps.add(TraceStep(
      title: 'Баланс = приход − расход',
      formulaText: '${formatThousands(intake.calories)} − '
          '${formatThousands(out.total)}',
      resultText: '= ${formatSignedKcal(balance)}',
    ));
    resultText = formatSignedKcal(balance);
  }

  // Целевая линия графика: `вес × темп% × 11`, округление до 10
  // (как в `EnergyBalanceChart._targetRounded`).
  String? note;
  if (latestWeight != null) {
    final target = ExpenditureConfig.targetDeficitKcalPerDay(
      latestWeight.weight,
      targetPacePercent,
    );
    final rounded = (target / 10).round() * 10;
    note = 'цель = вес × темп% × 11 = '
        '${_fmt1(latestWeight.weight)} × $targetPacePercent × 11 '
        '≈ −${formatThousands(rounded.abs())} ккал/день (линия на графике)';
  }

  return CalcTrace(
    title: 'Энергобаланс',
    subtitle: dateText,
    inputs: inputs,
    steps: steps,
    resultText: resultText,
    resultUnit: 'ккал',
    resultNote: note,
  );
}


// ─── §3.5 Среднесуточные (Тренд) ─────────────────────────────────────────────

/// Общий скелет трассы среднесуточного: отсечение по разрыву → таблица дней →
/// сумма → среднее. Значение и формат итога — в вызывающем билдере.
({
  List<TraceStep> steps,
  List<TraceDayRow> rows,
}) _avgSkeleton({
  required Iterable<DateKey> inRange,
  required Set<DateKey> kept,
  required bool excludeToday,
  required int rangeDays,
  required String Function(DateKey k) valueTextOf,
  required String? Function(DateKey k) sourceOf,
  required double Function(DateKey k) numValueOf,
}) {
  final sortedKept = kept.toList()..sort();
  final cutCount = inRange.length - kept.length;

  final steps = <TraceStep>[
    TraceStep(
      title: 'Отсечение по правилу «после последнего 5+-дневного разрыва»',
      resultText: cutCount > 0
          ? 'отсечено $cutCount дн. — в расчёт вошло ${kept.length} дн.'
          : 'отсечений нет — в расчёт вошло ${kept.length} дн.',
      note: excludeToday ? '«Сегодня» исключено — день не завершён' : null,
    ),
  ];

  final rows = [
    for (final k in sortedKept)
      TraceDayRow(
        dateText: _d(k),
        valueText: valueTextOf(k),
        sourceName: sourceOf(k),
      ),
  ];

  final sum = sortedKept.map(numValueOf).fold<double>(0, (a, b) => a + b);
  final summands = sortedKept.length <= 8
      ? sortedKept.map(numValueOf).map(_fmtKcal).join(' + ')
      : null;
  steps.add(TraceStep(
    title: 'Суммируем дни, вошедшие в расчёт',
    formulaText: summands,
    resultText: '= ${_fmtKcal(sum)}',
  ));
  steps.add(TraceStep(
    title: 'Среднее = сумма / дней с данными',
    formulaText: '${_fmtKcal(sum)} / ${sortedKept.length}',
    resultText: '= ${_fmtKcal(sum / sortedKept.length)}',
  ));

  return (steps: steps, rows: rows);
}

TraceInput _windowInput(int rangeDays, {required bool excludeToday}) =>
    TraceInput(
      label: 'Окно расчёта (сегмент Тренда)',
      valueText: '$rangeDays дней',
      kind: TraceSourceKind.computed,
      note: excludeToday ? '«Сегодня» исключено — день не завершён' : null,
    );

/// Среднесуточный сон, ч — по ночам с данными, БЕЗ исключения «сегодня»
/// (как геттер `DashboardViewModel.avgSleepHours`: у сна «сегодня» не
/// отсекается — ночь принадлежит своему дню сна, С3/С4).
AvgWithTrace<double> avgSleepWithTrace({
  required Map<DateKey, SleepDay> sleepCache,
  required DateTime start,
  required DateTime end,
  required int rangeDays,
}) {
  bool inRange(DateKey k) => k.value.isInsideInterval(start, end);
  final keys = sleepCache.keys.where(inRange);
  final kept = daysAfterLastGap(keys);

  if (kept.isEmpty) {
    return AvgWithTrace(
      null,
      CalcTrace(
        title: 'Среднесуточный сон',
        subtitle: 'окно $rangeDays дней',
        inputs: [_windowInput(rangeDays, excludeToday: false)],
        steps: const [
          TraceStep(title: 'Ночей с данными в окне нет', resultText: '→ среднего нет'),
        ],
        resultText: '—',
        resultUnit: 'ч',
      ),
    );
  }

  final skeleton = _avgSkeleton(
    inRange: keys,
    kept: kept,
    excludeToday: false,
    rangeDays: rangeDays,
    valueTextOf: (k) => '${_fmt1(sleepCache[k]!.total)} ч',
    sourceOf: (_) => null,
    numValueOf: (k) => sleepCache[k]!.total,
  );

  final value =
      kept.map((k) => sleepCache[k]!.total).reduce((a, b) => a + b) / kept.length;
  return AvgWithTrace(
    value,
    CalcTrace(
      title: 'Среднесуточный сон',
      subtitle: 'окно $rangeDays дней',
      inputs: [_windowInput(rangeDays, excludeToday: false)],
      steps: skeleton.steps,
      resultText: value.toStringAsFixed(1),
      resultUnit: 'ч',
      resultNote: 'по ${kept.length} дн.',
      dayRows: skeleton.rows,
      dayRowsCollapsedByDefault: rangeDays == 90,
    ),
  );
}


/// Среднесуточные шаги — по дням с записями, без «сегодня» (A.8);
/// итог `.round()`, как геттер `avgSteps`.
AvgWithTrace<int> avgStepsWithTrace({
  required Map<DateKey, StepsDay> stepsCache,
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required int rangeDays,
}) {
  final todayKey = DateKey(today);
  bool inRange(DateKey k) =>
      k.value.isInsideInterval(start, end) && k != todayKey;
  final keys = stepsCache.keys.where(inRange);
  final kept = daysAfterLastGap(keys);

  int? value() {
    if (kept.isEmpty) return null;
    var total = 0;
    for (final k in kept) {
      total += stepsCache[k]!.steps;
    }
    return (total / kept.length).round();
  }

  final skeleton = _avgSkeleton(
    inRange: keys,
    kept: kept,
    excludeToday: true,
    rangeDays: rangeDays,
    valueTextOf: (k) => formatThousands(stepsCache[k]!.steps),
    sourceOf: (k) => stepsCache[k]!.sourcePackage,
    numValueOf: (k) => stepsCache[k]!.steps.toDouble(),
  );

  final v = value();
  return AvgWithTrace(
    v,
    CalcTrace(
      title: 'Среднесуточные шаги',
      subtitle: 'окно $rangeDays дней',
      inputs: [_windowInput(rangeDays, excludeToday: true)],
      steps: kept.isEmpty
          ? const [
              TraceStep(title: 'Дней с записями в окне нет', resultText: '→ среднего нет')
            ]
          : skeleton.steps,
      resultText: v == null ? '—' : formatThousands(v),
      resultUnit: 'шагов',
      resultNote: kept.isEmpty ? null : 'по ${kept.length} дн.',
      dayRows: kept.isEmpty ? null : skeleton.rows,
      dayRowsCollapsedByDefault: rangeDays == 90,
    ),
  );
}

/// Среднесуточный приход, ккал — по дням с приходом, без «сегодня» (A.8).
AvgWithTrace<double> avgIntakeWithTrace({
  required Map<DateKey, NutritionDay> nutritionCache,
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required int rangeDays,
}) {
  final todayKey = DateKey(today);
  bool inRange(DateKey k) =>
      k.value.isInsideInterval(start, end) && k != todayKey;
  final keys = nutritionCache.keys.where(inRange);
  final kept = daysAfterLastGap(keys);

  if (kept.isEmpty) {
    return AvgWithTrace(
      null,
      CalcTrace(
        title: 'Среднесуточный приход',
        subtitle: 'окно $rangeDays дней',
        inputs: [_windowInput(rangeDays, excludeToday: true)],
        steps: const [
          TraceStep(title: 'Дней с приходом в окне нет', resultText: '→ среднего нет')
        ],
        resultText: '—',
        resultUnit: 'ккал',
      ),
    );
  }

  final skeleton = _avgSkeleton(
    inRange: keys,
    kept: kept,
    excludeToday: true,
    rangeDays: rangeDays,
    valueTextOf: (k) => formatThousands(nutritionCache[k]!.calories),
    sourceOf: (k) => nutritionCache[k]!.sourcePackage,
    numValueOf: (k) => nutritionCache[k]!.calories,
  );

  final value = kept
      .map((k) => nutritionCache[k]!.calories)
      .reduce((a, b) => a + b) / kept.length;
  return AvgWithTrace(
    value,
    CalcTrace(
      title: 'Среднесуточный приход',
      subtitle: 'окно $rangeDays дней',
      inputs: [_windowInput(rangeDays, excludeToday: true)],
      steps: skeleton.steps,
      resultText: formatThousands(value),
      resultUnit: 'ккал',
      resultNote: 'по ${kept.length} дн.',
      dayRows: skeleton.rows,
      dayRowsCollapsedByDefault: rangeDays == 90,
    ),
  );
}


/// Средние макросы (Б/Ж/У, г/день) — по дням с приходом, без «сегодня»;
/// день без макроса считается нулём (решение 2026-09-14).
AvgMacrosWithTrace avgMacrosWithTrace({
  required Map<DateKey, NutritionDay> nutritionCache,
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required int rangeDays,
}) {
  final todayKey = DateKey(today);
  bool inRange(DateKey k) =>
      k.value.isInsideInterval(start, end) && k != todayKey;
  final keys = nutritionCache.keys.where(inRange);
  final kept = daysAfterLastGap(keys);

  if (kept.isEmpty) {
    return AvgMacrosWithTrace(
      trace: CalcTrace(
        title: 'Средние макросы',
        subtitle: 'окно $rangeDays дней',
        inputs: [_windowInput(rangeDays, excludeToday: true)],
        steps: const [
          TraceStep(title: 'Дней с приходом в окне нет', resultText: '→ среднего нет')
        ],
        resultText: '—',
        resultUnit: 'г',
      ),
    );
  }

  final skeleton = _avgSkeleton(
    inRange: keys,
    kept: kept,
    excludeToday: true,
    rangeDays: rangeDays,
    valueTextOf: (k) => formatThousands(nutritionCache[k]!.calories),
    sourceOf: (k) => nutritionCache[k]!.sourcePackage,
    numValueOf: (k) => nutritionCache[k]!.calories,
  );

  final n = kept.length;
  double avgOf(double? Function(NutritionDay d) f) =>
      kept.map((k) => f(nutritionCache[k]!) ?? 0).reduce((a, b) => a + b) / n;
  final protein = avgOf((d) => d.protein);
  final fat = avgOf((d) => d.fat);
  final carbs = avgOf((d) => d.carbs);

  return AvgMacrosWithTrace(
    protein: protein,
    fat: fat,
    carbs: carbs,
    trace: CalcTrace(
      title: 'Средние макросы',
      subtitle: 'окно $rangeDays дней',
      inputs: [_windowInput(rangeDays, excludeToday: true)],
      steps: [
        ...skeleton.steps,
        TraceStep(
          title: 'Средние Б/Ж/У — по одним и тем же дням с приходом',
          formulaText: 'белки ${_fmt1(protein)} · жиры ${_fmt1(fat)} · '
              'углеводы ${_fmt1(carbs)} (÷ $n)',
          resultText: '= ${protein.round()} / ${fat.round()} / ${carbs.round()} г',
          note: 'день без макроса = 0',
        ),
      ],
      resultText: '${protein.round()} / ${fat.round()} / ${carbs.round()}',
      resultUnit: 'г (Б/Ж/У)',
      resultNote: 'по $n дн. · день без макроса = 0',
      dayRows: skeleton.rows,
      dayRowsCollapsedByDefault: rangeDays == 90,
    ),
  );
}

/// Среднесуточный расход, ккал — по дням с рассчитанным BMR, без «сегодня».
AvgWithTrace<double> avgExpenditureWithTrace({
  required Map<DateKey, ExpenditureDay> expenditureCache,
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required int rangeDays,
}) {
  final todayKey = DateKey(today);
  bool inRange(DateKey k) =>
      k.value.isInsideInterval(start, end) && k != todayKey;
  final keys = expenditureCache.keys.where(inRange);
  final kept = daysAfterLastGap(keys);

  if (kept.isEmpty) {
    return AvgWithTrace(
      null,
      CalcTrace(
        title: 'Среднесуточный расход',
        subtitle: 'окно $rangeDays дней',
        inputs: [_windowInput(rangeDays, excludeToday: true)],
        steps: const [
          TraceStep(title: 'Дней с рассчитанным BMR в окне нет', resultText: '→ среднего нет')
        ],
        resultText: '—',
        resultUnit: 'ккал',
      ),
    );
  }

  final skeleton = _avgSkeleton(
    inRange: keys,
    kept: kept,
    excludeToday: true,
    rangeDays: rangeDays,
    valueTextOf: (k) => '≈ ${formatThousands(expenditureCache[k]!.total)}',
    sourceOf: (_) => null,
    numValueOf: (k) => expenditureCache[k]!.total,
  );

  final value = kept
      .map((k) => expenditureCache[k]!.total)
      .reduce((a, b) => a + b) / kept.length;
  return AvgWithTrace(
    value,
    CalcTrace(
      title: 'Среднесуточный расход',
      subtitle: 'окно $rangeDays дней',
      inputs: [
        _windowInput(rangeDays, excludeToday: true),
        const TraceInput(
          label: 'Знаменатель',
          valueText: 'дни с рассчитанным BMR',
          kind: TraceSourceKind.formula,
        ),
      ],
      steps: skeleton.steps,
      resultText: '≈ ${formatThousands(value)}',
      resultUnit: 'ккал',
      resultNote: 'по ${kept.length} дн.',
      dayRows: skeleton.rows,
      dayRowsCollapsedByDefault: rangeDays == 90,
    ),
  );
}


// ─── §3.6 Темп (Саммари) ─────────────────────────────────────────────────────

/// Трасса темпа снижения веса. [summary] — результат
/// `RecommendationEngine.compute` (`null` → трасса-объяснение «данных
/// недостаточно»), [engineEmaCache] — EMA с периодом движка
/// (`RecommendationConfig.engineEmaPeriod`), для цепочки шагов.
CalcTrace paceTrace({
  required Map<DateKey, WeightDay> weightCache,
  required Map<DateKey, WeightDay> engineEmaCache,
  required DateTime today,
  required double targetPacePercent,
  required WeeklySummary? summary,
}) {
  final inputs = <TraceInput>[
    TraceInput(
      label: 'Целевой темп',
      valueText: '$targetPacePercent %/нед',
      kind: TraceSourceKind.settings,
    ),
    const TraceInput(
      label: 'Допуск «в темпе»',
      valueText: '±${RecommendationConfig.paceTolerance} п.п.',
      kind: TraceSourceKind.formula,
    ),
    const TraceInput(
      label: 'EMA-период движка',
      valueText: '${RecommendationConfig.engineEmaPeriod}',
      kind: TraceSourceKind.formula,
      note: 'не связан с периодом EMA дашборда',
    ),
  ];

  if (summary == null) {
    // EMA-точек окна после отсечения < 5 — трасса-объяснение порога.
    final windowStart = DateKey(today.subtract(const Duration(days: 6)));
    final inWindow = engineEmaCache.values
        .where((e) => !e.date.value.isBefore(windowStart.value))
        .length;
    return CalcTrace(
      title: 'Темп',
      subtitle: 'окно 7 дней',
      inputs: inputs,
      steps: [
        TraceStep(
          title: 'Точек EMA в окне после отсечения',
          resultText:
              '$inWindow < ${RecommendationConfig.minWeightPointsInWindow}',
          note: 'нужно ≥ ${RecommendationConfig.minWeightPointsInWindow} '
              'взвешиваний за неделю (решение пользователя 2026-09-18) — '
              'саммари не готово',
        ),
      ],
      resultText: 'данных недостаточно',
      emaRows: _emaRows(weightCache, engineEmaCache),
    );
  }

  final first = engineEmaCache[DateKey(summary.rangeStart)]!;
  final last = engineEmaCache[DateKey(summary.rangeEnd)]!;
  final daysBetween = summary.rangeEnd.difference(summary.rangeStart).inDays;
  final rawPct = (last.weight - first.weight) / first.weight * 100;
  final statusTitle = switch (summary.status) {
    PaceStatus.inPace => 'в темпе',
    PaceStatus.tooSlow => 'слишком медленно',
    PaceStatus.tooFast => 'слишком быстро',
  };

  final steps = <TraceStep>[
    TraceStep(
      title: 'EMA-точки окна после отсечения',
      resultText: 'первая ${_d(first.date)} · последняя ${_d(last.date)} · '
          'между ними $daysBetween дн.',
    ),
    TraceStep(
      title: 'Процент изменения EMA',
      formulaText:
          '(${_fmt1(last.weight)} − ${_fmt1(first.weight)}) / ${_fmt1(first.weight)} × 100',
      resultText: '= ${rawPct.toStringAsFixed(1)}%',
    ),
    TraceStep(
      title: 'Нормализация к неделе',
      formulaText: '${rawPct.toStringAsFixed(1)} × 7 / $daysBetween',
      resultText: '= ${summary.actualPacePercent.toStringAsFixed(1)} %/нед',
    ),
    TraceStep(
      title: 'Изменение сглаженного веса',
      formulaText: '${_fmt1(last.weight)} − ${_fmt1(first.weight)}',
      resultText: '= ${_signed1(summary.weightChangeKg)} кг за неделю',
    ),
    TraceStep(
      title: 'Статус: |факт| против цель ± ${RecommendationConfig.paceTolerance}',
      formulaText:
          '${summary.actualPacePercent.abs().toStringAsFixed(2)} против '
          '$targetPacePercent ± ${RecommendationConfig.paceTolerance}',
      resultText: '→ $statusTitle',
    ),
  ];

  final sign = summary.actualPacePercent < 0 ? '−' : '+';
  return CalcTrace(
    title: 'Темп',
    subtitle: 'окно 7 дней',
    inputs: inputs,
    steps: steps,
    resultText: '$sign${summary.actualPacePercent.abs().toStringAsFixed(1)}%',
    resultUnit: '%/нед',
    resultNote: '${_signed1(summary.weightChangeKg)} кг за неделю',
    emaRows: _emaRows(weightCache, engineEmaCache),
  );
}


// ─── §3.7 Энергобаланс недели (Саммари) ──────────────────────────────────────

/// Трасса карточки «Энергобаланс недели»: окно `today−6 .. today−1`, таблица
/// дней и 4 средних из [WeeklyEnergyStats] (значения — из
/// `computeEnergyStats`, не пересчитываются).
CalcTrace energyWeekTrace({
  required WeeklyEnergyStats? stats,
  required DateTime today,
}) {
  final subtitle =
      'окно 6 дней (${_d(DateKey(today.subtract(const Duration(days: 6))))} — '
      '${_d(DateKey(today.subtract(const Duration(days: 1))))})';

  if (stats == null) {
    return CalcTrace(
      title: 'Энергобаланс недели',
      subtitle: subtitle,
      inputs: const [],
      steps: const [
        TraceStep(
          title: 'Дней с приходом в окне меньше 2',
          resultText: 'энергостаты скрыты — движок на текстах Фазы 5',
          note: 'правило C.1: блок показывается от 2 дней с питанием',
        ),
      ],
      resultText: '—',
      resultUnit: 'ккал/день',
    );
  }

  final rows = [
    for (final r in stats.dayRows)
      TraceDayRow(
        dateText: _d(r.date),
        valueText: r.intakeKcal == null ? '—' : formatThousands(r.intakeKcal!),
        value2Text: r.expenditureKcal == null
            ? '—'
            : '≈ ${formatThousands(r.expenditureKcal!)}',
        value3Text: r.balanceKcal == null
            ? 'не считается'
            : formatSignedKcal(r.balanceKcal!),
      ),
  ];

  final steps = <TraceStep>[
    TraceStep(
      title: 'Средний приход = сумма / дни с приходом',
      resultText: '= ${formatThousands(stats.avgIntake)} '
          '(по ${stats.intakeDays} дн. с приходом)',
    ),
    TraceStep(
      title: 'Средний расход = сумма / дни с рассчитанным BMR',
      resultText: stats.avgExpenditure == null
          ? 'расхода нет'
          : '= ≈ ${formatThousands(stats.avgExpenditure!)}',
    ),
    TraceStep(
      title: 'Средний баланс = сумма / дни с приходом И расходом',
      resultText: stats.avgBalance == null
          ? 'дней с приходом и расходом нет'
          : '= ${formatSignedKcal(stats.avgBalance!)}',
    ),
    TraceStep(
      title: 'Ожидаемый темп = средний баланс × 7 / 7700',
      formulaText: stats.avgBalance == null
          ? null
          : '${formatSignedKcal(stats.avgBalance!)} × 7 / '
              '${ExpenditureConfig.kcalPerKgFat}',
      resultText: stats.expectedKgPerWeek == null
          ? '—'
          : '= ${_signed2(stats.expectedKgPerWeek!)} кг/нед',
    ),
  ];

  final exp = stats.avgExpenditure;
  final expected = stats.expectedKgPerWeek;
  return CalcTrace(
    title: 'Энергобаланс недели',
    subtitle: subtitle,
    inputs: const [],
    steps: steps,
    resultText:
        stats.avgBalance == null ? '—' : formatSignedKcal(stats.avgBalance!),
    resultUnit: 'ккал/день · средний баланс',
    resultNote: 'приход ${formatThousands(stats.avgIntake)} · '
        'расход ${exp == null ? '—' : '≈ ${formatThousands(exp)}'} · '
        'ожидание ${expected == null ? '—' : '${_signed2(expected)} кг/нед'}',
    dayRows: rows,
  );
}


// ─── §3.8 Рекомендация (Саммари) ─────────────────────────────────────────────

/// Трасса текста рекомендации: динамическая дельта v2 (§0 п. 13) или дословный
/// текст Фазы 5 при отсутствии энергостатов. Итог — `recommendationText`
/// дословно (совпадение фиксируется тестом).
CalcTrace recommendationTrace({
  required WeeklySummary? summary,
  required WeeklyEnergyStats? energyStats,
  required double? weightKg,
}) {
  if (summary == null) {
    // Саммари не готово (<5 взвешиваний за неделю) — текста рекомендации нет.
    return const CalcTrace(
      title: 'Рекомендация',
      subtitle: 'на следующую неделю',
      inputs: [],
      steps: [
        TraceStep(
          title: 'Саммари не готово',
          resultText: 'данных недостаточно — текста рекомендации нет',
        ),
      ],
      resultText: '—',
    );
  }

  final inputs = <TraceInput>[
    TraceInput(
      label: 'Целевой темп',
      valueText: '${summary.targetPacePercent} %/нед',
      kind: TraceSourceKind.settings,
    ),
    TraceInput(
      label: 'Фактический темп',
      valueText: '${summary.actualPacePercent.toStringAsFixed(1)} %/нед',
      kind: TraceSourceKind.computed,
      note: 'из трассы темпа',
    ),
    TraceInput(
      label: 'Коридор дельты',
      valueText:
          '${ExpenditureConfig.minDeltaKcal.toStringAsFixed(0)}–'
          '${ExpenditureConfig.maxDeltaKcal.toStringAsFixed(0)} '
          'ккал/день, округление до 10',
      kind: TraceSourceKind.formula,
    ),
  ];
  if (weightKg != null) {
    inputs.add(TraceInput(
      label: 'Вес',
      valueText: '${_fmt1(weightKg)} кг',
      kind: TraceSourceKind.computed,
      note: 'последний резолвленный вес',
    ));
  }
  if (energyStats != null) {
    inputs.add(TraceInput(
      label: 'Средний приход',
      valueText: formatThousands(energyStats.avgIntake),
      kind: TraceSourceKind.computed,
      note: 'из энергобаланса недели',
    ));
  }

  final statusTitle = switch (summary.status) {
    PaceStatus.inPace => 'в темпе',
    PaceStatus.tooSlow => 'слишком медленно',
    PaceStatus.tooFast => 'слишком быстро',
  };

  // Ветка v2 — условие входа то же, что в движке `_recommendationFor`.
  final useV2 = energyStats != null && weightKg != null;
  final needsBalance = summary.status == PaceStatus.inPace;
  final hasBalance = energyStats?.avgBalance != null;
  final v2 = useV2 && (!needsBalance || hasBalance);

  final steps = <TraceStep>[];
  if (v2) {
    final stats = energyStats;
    final diffPp =
        (summary.actualPacePercent - summary.targetPacePercent).abs();
    final raw = weightKg * diffPp * ExpenditureConfig.kcalPerPacePointPerKg;
    final clamped =
        raw.clamp(ExpenditureConfig.minDeltaKcal, ExpenditureConfig.maxDeltaKcal);
    final delta = (clamped / 10).round() * 10;

    steps.add(TraceStep(
      title: 'Дельта = вес × |цель − факт| × 11',
      formulaText: '${_fmt1(weightKg)} × ${diffPp.toStringAsFixed(2)} × '
          '${ExpenditureConfig.kcalPerPacePointPerKg}',
      resultText: '= ${_fmtKcal(raw)}',
    ));
    steps.add(TraceStep(
      title: 'Коридор ${ExpenditureConfig.minDeltaKcal.toStringAsFixed(0)}–'
          '${ExpenditureConfig.maxDeltaKcal.toStringAsFixed(0)}',
      resultText: raw == clamped
          ? 'в коридоре — без изменений (${_fmtKcal(raw)})'
          : 'кламп: ${_fmtKcal(raw)} → ${_fmtKcal(clamped)}',
    ));
    steps.add(TraceStep(
      title: 'Округление до 10',
      formulaText: '(${_fmtKcal(clamped)} / 10).round() × 10',
      resultText: '= $delta',
    ));
    final intakeNew = summary.status == PaceStatus.tooFast
        ? stats.avgIntake + delta
        : stats.avgIntake - delta;
    steps.add(TraceStep(
      title: 'Новый приход = средний приход ∓ дельта',
      formulaText:
          '${_fmtKcal(stats.avgIntake)} ${summary.status == PaceStatus.tooFast ? '+' : '−'} $delta',
      resultText: '= ${_fmtKcal(intakeNew)}',
    ));
    steps.add(TraceStep(
      title: 'Шаблон v2 по статусу «$statusTitle»',
      resultText: summary.recommendationText,
    ));
  } else {
    steps.add(TraceStep(
      title: 'Энергостаты недоступны',
      resultText: 'данных питания < 2 дней — тексты Фазы 5 без чисел',
      note: 'движок регрессирует на дословные шаблоны Фазы 5 (C.2)',
    ));
    steps.add(TraceStep(
      title: 'Шаблон Фазы 5',
      formulaText: 'подстановка {actual} = '
          '${summary.actualPacePercent.abs().toStringAsFixed(1)}, '
          '{target} = ${summary.targetPacePercent.toStringAsFixed(1)}',
      resultText: summary.recommendationText,
    ));
  }

  return CalcTrace(
    title: 'Рекомендация',
    subtitle: 'на следующую неделю',
    inputs: inputs,
    steps: steps,
    resultText: summary.recommendationText,
  );
}


// ─── §3.9 Сглаженный вес («Сегодня») ─────────────────────────────────────────

/// Трасса большого числа на вкладке «Сегодня»: сглаженный вес = последняя
/// точка EMA-линии дашборда (период 3/5/10 — зависит от длины диапазона).
CalcTrace smoothedWeightTrace({
  required double? smoothedWeight,
  required int emaPeriod,
  required Map<DateKey, WeightDay> weightCache,
  required Map<DateKey, WeightDay> emaCache,
}) {
  WeightDay? lastOf(Map<DateKey, WeightDay> cache) => cache.isEmpty
      ? null
      : (cache.values.toList()..sort((a, b) => a.date.compareTo(b.date))).last;
  final lastWeight = lastOf(weightCache);
  final lastEma = lastOf(emaCache);

  final inputs = <TraceInput>[
    if (lastWeight != null)
      TraceInput(
        label: 'Последнее взвешивание — ${_d(lastWeight.date)}',
        valueText: '${_fmt1(lastWeight.weight)} кг',
        kind: lastWeight.source == DataSource.manual
            ? TraceSourceKind.manual
            : TraceSourceKind.healthConnect,
        sourceName: lastWeight.sourcePackage,
      ),
    TraceInput(
      label: 'EMA-период отображения',
      valueText: '$emaPeriod',
      kind: TraceSourceKind.computed,
      note: 'зависит от длины диапазона: 7 дн. → 3, 30 дн. → 5, 90 дн. → 10',
    ),
  ];

  if (smoothedWeight == null || lastEma == null) {
    return CalcTrace(
      title: 'Сглаженный вес',
      inputs: inputs,
      steps: const [
        TraceStep(title: 'Точек веса нет', resultText: '→ EMA-линия пуста'),
      ],
      resultText: '—',
      resultUnit: 'кг',
    );
  }

  final k = 2 / (emaPeriod + 1);
  return CalcTrace(
    title: 'Сглаженный вес',
    subtitle: 'последняя точка EMA-линии',
    inputs: inputs,
    steps: [
      TraceStep(
        title: 'Сглаженный вес = последняя точка EMA-линии',
        formulaText: 'EMA за ${_d(lastEma.date)}',
        resultText: '= ${_fmt1(smoothedWeight)}',
        note: 'EMA: ema = (вес − ema_prev) × k + ema_prev, '
            'k = 2 / ($emaPeriod + 1) = ${k.toStringAsFixed(3)}',
      ),
    ],
    resultText: _fmt1(smoothedWeight),
    resultUnit: 'кг',
    emaRows: _emaRows(weightCache, emaCache),
  );
}

