import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:health/health.dart';

/// Слой бизнес-логики: резолюция приоритета источников (Tier 1 → Tier 2).
///
/// **Чистые синхронные функции** — работают с предзагруженными данными,
/// не вызывают репозиторий. Это позволяет:
/// 1. Тестировать без моков репозитория — просто передаёшь массив точек.
/// 2. Не делать N запросов на N дат — данные грузятся батчем в ViewModel
///    (⚠️ критичное требование из `systemPatterns.md`).
///
/// **Пакет источника (Фаза 6, A0):** на Android у пакета `health` 13.3.1/13.3.2
/// `sourceId` ВСЕГДА пустой (`HealthDataConverter.createBaseRecord` отдаёт
/// захардкоженный `""`), реальный пакет приложения приходит в `sourceName` =
/// `metadata.dataOrigin.packageName`. Поэтому [sourcePackageOf] берёт
/// `sourceName`, а `sourceId` — только fallback (iOS/будущие версии).
///
/// **Tier 1** (ручной ввод) — точка с `sourcePackage` = [appPackageId].
/// Всегда побеждает, если существует на дату.
///
/// **Tier 2** (Фаза 6, C.2):
/// 1. Отбрасываются источники с решением `refused` ([ConfirmDecision.refused]).
/// 2. Выбрано приложение ([SourceSelection.app]) — только его точки.
/// 3. «Авто»: вес — last-wins по `dateFrom`; шаги — «один источник на день»:
///    источник с максимальной суммой за день, значение = сумма его точек
///    (замена нативного `aggregate()`, техриски №2/№4 закрыты архитектурно).
/// 4. Пригодных точек нет → `null`.
class HealthDataProcessor {
  /// Идентификатор пакета приложения — определяет Tier 1 записи.
  final String appPackageId;

  HealthDataProcessor({required this.appPackageId});

  // ─── Пакет источника точки ─────────────────────────────────────────────────

  /// Пакет приложения-источника точки: `sourceName` (Android — реальный
  /// `dataOrigin.packageName`), fallback — `sourceId` (iOS/будущие версии).
  ///
  /// Один источник истины для Tier 1, списка источников и `sourcePackage`
  /// в результатах — не сравнивать `sourceId` напрямую (он пуст на Android).
  static String sourcePackageOf(HealthDataPoint point) {
    final name = point.sourceName;
    if (name.isNotEmpty) return name;
    return point.sourceId;
  }

  /// Наша ли это точка (Tier 1 — ручной ввод через Cut Metrics)?
  bool isOurPoint(HealthDataPoint point) =>
      sourcePackageOf(point) == appPackageId;

  // ─── Вес: резолюция на одну дату ────────────────────────────────────────────

  /// Резолюция веса для конкретной даты.
  ///
  /// 1. Есть наша точка (Tier 1)? → `WeightDay(source: manual)` — последняя
  ///    по времени.
  /// 2. Иначе Tier 2: refused-фильтр → выбранный источник («Авто» — last-wins).
  /// 3. Нет пригодных данных → `null`.
  ///
  /// [decisions] — карта пакет → решение пользователя (B.1),
  /// [selection] — выбранный источник для метрики (C.1).
  WeightDay? resolveWeightForDate(
    DateKey date,
    List<HealthDataPoint> weightPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
  }) {
    final dayPoints = weightPoints
        .where((p) => DateKey(p.dateFrom) == date)
        .toList();
    if (dayPoints.isEmpty) return null;

    // Tier 1: ручная запись — всегда побеждает.
    final ourPoints = dayPoints.where(isOurPoint).toList();
    if (ourPoints.isNotEmpty) {
      final last = _lastByTime(ourPoints);
      return WeightDay(
        date: date,
        weight: _numericValue(last),
        source: DataSource.manual,
        sourcePackage: appPackageId,
      );
    }

    // Tier 2: refused-фильтр + выбор источника, last-wins.
    final pool = _tier2Pool(dayPoints, decisions, selection);
    if (pool.isEmpty) return null;
    final last = _lastByTime(pool);
    return WeightDay(
      date: date,
      weight: _numericValue(last),
      source: DataSource.external,
      sourcePackage: sourcePackageOf(last),
    );
  }

  // ─── Шаги: резолюция на одну дату ───────────────────────────────────────────

  /// Резолюция шагов для конкретной даты — по сырым точкам (Фаза 6, A2).
  ///
  /// 1. Есть наша точка (Tier 1)? → `StepsDay(source: manual)` — последняя по
  ///    времени (после идемпотентной записи delete-then-write она одна).
  /// 2. Иначе Tier 2, правило «один источник на день»:
  ///    - выбран источник ([SourceSelection.app]) — сумма его точек за день;
  ///    - «Авто» — источник с максимальной суммой за день среди неотклонённых;
  ///      если в дне несколько источников, вызывается [onWarn] (диагностика
  ///      выбора — логируется вызывающей стороной, процессор остаётся чистым).
  /// 3. Нет пригодных данных → `null`.
  StepsDay? resolveStepsForDate(
    DateKey date,
    List<HealthDataPoint> stepsPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
    void Function(String message)? onWarn,
  }) {
    final dayPoints = stepsPoints
        .where((p) => DateKey(p.dateFrom) == date)
        .toList();
    if (dayPoints.isEmpty) return null;

    // Tier 1: ручная запись — всегда побеждает.
    final ourPoints = dayPoints.where(isOurPoint).toList();
    if (ourPoints.isNotEmpty) {
      final last = _lastByTime(ourPoints);
      return StepsDay(
        date: date,
        steps: _numericValue(last).toInt(),
        source: DataSource.manual,
        sourcePackage: appPackageId,
      );
    }

    final pool = _tier2Pool(dayPoints, decisions, selection);
    if (pool.isEmpty) return null;

    if (selection.isAuto) {
      // «Авто»: группируем по источникам, берём максимальную сумму за день.
      final bySource = <String, List<HealthDataPoint>>{};
      for (final p in pool) {
        bySource.putIfAbsent(sourcePackageOf(p), () => []).add(p);
      }
      if (bySource.length > 1) {
        onWarn?.call(
          'шаги $date: несколько источников (${bySource.keys.join(', ')}) — '
          'взят источник с максимальной суммой за день',
        );
      }
      var bestSource = bySource.keys.first;
      var bestSum = -1;
      for (final entry in bySource.entries) {
        final sum = entry.value.fold<int>(
          0,
          (acc, p) => acc + _numericValue(p).toInt(),
        );
        if (sum > bestSum) {
          bestSum = sum;
          bestSource = entry.key;
        }
      }
      if (bestSum <= 0) return null;
      return StepsDay(
        date: date,
        steps: bestSum,
        source: DataSource.external,
        sourcePackage: bestSource,
      );
    }

    // Выбран конкретный источник: сумма его точек за день.
    final sum = pool.fold<int>(
      0,
      (acc, p) => acc + _numericValue(p).toInt(),
    );
    if (sum <= 0) return null;
    return StepsDay(
      date: date,
      steps: sum,
      source: DataSource.external,
      sourcePackage: selection.package,
    );
  }

  // ─── Батчевая резолюция на диапазон ─────────────────────────────────────────
  //
  // ⚠️ Критично: резолюция должна работать батчево на весь диапазон дат,
  // а не отдельным запросом на каждый день (systemPatterns.md).
  // Методы ниже принимают предзагруженные данные и резолвят все даты in-memory.

  /// Резолюция веса для всех дат в предзагруженном списке точек.
  ///
  /// Возвращает Map с резолютированными значениями для каждой даты, где есть
  /// хотя бы одна пригодная запись.
  Map<DateKey, WeightDay> resolveWeightForAllDates(
    List<HealthDataPoint> weightPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
  }) {
    final result = <DateKey, WeightDay>{};

    // Группируем по дате
    final byDate = <DateKey, List<HealthDataPoint>>{};
    for (final p in weightPoints) {
      byDate.putIfAbsent(DateKey(p.dateFrom), () => []).add(p);
    }

    for (final entry in byDate.entries) {
      final resolved = resolveWeightForDate(
        entry.key,
        weightPoints,
        decisions: decisions,
        selection: selection,
      );
      if (resolved != null) result[entry.key] = resolved;
    }

    return result;
  }

  /// Резолюция шагов для всех дат — только по сырым точкам (A2: aggregate-API
  /// удалены из архитектуры, один `fetchRawData` на диапазон — Фаза 4, DoD 3).
  Map<DateKey, StepsDay> resolveStepsForAllDates(
    List<HealthDataPoint> stepsPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
    void Function(String message)? onWarn,
  }) {
    final result = <DateKey, StepsDay>{};

    final byDate = <DateKey, List<HealthDataPoint>>{};
    for (final p in stepsPoints) {
      byDate.putIfAbsent(DateKey(p.dateFrom), () => []).add(p);
    }

    for (final entry in byDate.entries) {
      final resolved = resolveStepsForDate(
        entry.key,
        stepsPoints,
        decisions: decisions,
        selection: selection,
        onWarn: onWarn,
      );
      if (resolved != null) result[entry.key] = resolved;
    }

    return result;
  }

  // ─── Питание: резолюция «один источник на день» (Фаза 7, A.6) ──────────────
  //
  // Паттерн Фазы 6 A2/C с одним принципиальным отличием: авто-правило НЕ
  // «максимальная сумма» (для калорий оно систематически выбирало бы самый
  // завышающий источник). Авто = источник с наибольшим числом дней, имеющих
  // записи, в загруженном диапазоне; при равенстве — больше записей; при
  // равенстве — большая сумма калорий.

  /// Резолюция питания для конкретной даты (значение из полного списка точек —
  /// авто-победитель считается по всему диапазону, A.6).
  NutritionDay? resolveNutritionForDate(
    DateKey date,
    List<HealthDataPoint> nutritionPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
    void Function(String message)? onWarn,
  }) {
    return resolveNutritionForAllDates(
      nutritionPoints,
      decisions: decisions,
      selection: selection,
      onWarn: onWarn,
    )[date];
  }

  /// Резолюция питания для всех дат — один победивший источник на весь
  /// диапазон (A.6), ценность дня = сумма калорий и макросов только его
  /// записей (записи внутри дня суммируются — трекеры пишут по пункту/приёму).
  ///
  /// Tier 1: наш «Итог дня» всегда побеждает для своей даты. День без записей
  /// победителя = «нет данных» → не попадает в результат («нет данных ≠ 0»).
  Map<DateKey, NutritionDay> resolveNutritionForAllDates(
    List<HealthDataPoint> nutritionPoints, {
    Map<String, ConfirmDecision> decisions = const {},
    SourceSelection selection = const SourceSelection.auto(),
    void Function(String message)? onWarn,
  }) {
    final byDate = <DateKey, List<HealthDataPoint>>{};
    for (final p in nutritionPoints) {
      byDate.putIfAbsent(DateKey(p.dateFrom), () => []).add(p);
    }

    // Tier 2-пул на весь диапазон: не наши, не отклонённые, при выбранном
    // источнике — только его точки (C.2, шаги 1–2).
    final pool = _tier2Pool(nutritionPoints, decisions, selection);
    final winner = _autoWinnerNutritionSource(pool);

    final result = <DateKey, NutritionDay>{};
    for (final entry in byDate.entries) {
      final date = entry.key;
      final dayPoints = entry.value;

      // Tier 1: ручной «Итог дня» — всегда побеждает.
      final ourPoints = dayPoints.where(isOurPoint).toList();
      if (ourPoints.isNotEmpty) {
        result[date] = _sumNutrition(date, ourPoints, DataSource.manual, appPackageId);
        continue;
      }

      if (winner == null) continue;
      final winnerPoints =
          dayPoints.where((p) => sourcePackageOf(p) == winner).toList();
      if (winnerPoints.isEmpty) continue;

      final daySources = dayPoints.map(sourcePackageOf).toSet();
      if (daySources.length > 1) {
        onWarn?.call(
          'питание $date: несколько источников (${daySources.join(', ')}) — '
          'взят источник с наибольшим покрытием дней ($winner)',
        );
      }
      result[date] = _sumNutrition(date, winnerPoints, DataSource.external, winner);
    }

    return result;
  }

  /// Авто-правило питания (A.6): источник с наибольшим числом дней, имеющих
  /// записи; при равенстве — больше записей; при равенстве — большая сумма
  /// калорий. Пул уже отфильтрован (refused/selection) — группируем его как есть.
  String? _autoWinnerNutritionSource(List<HealthDataPoint> pool) {
    if (pool.isEmpty) return null;

    final daysBySource = <String, Set<DateKey>>{};
    final countBySource = <String, int>{};
    final kcalBySource = <String, double>{};
    for (final p in pool) {
      final source = sourcePackageOf(p);
      daysBySource.putIfAbsent(source, () => {}).add(DateKey(p.dateFrom));
      countBySource[source] = (countBySource[source] ?? 0) + 1;
      kcalBySource[source] =
          (kcalBySource[source] ?? 0) + (_nutritionValue(p).calories ?? 0);
    }

    var best = daysBySource.keys.first;
    for (final source in daysBySource.keys) {
      if (source == best) continue;
      final bestDays = daysBySource[best]!.length;
      final days = daysBySource[source]!.length;
      final better = days > bestDays ||
          (days == bestDays &&
              (countBySource[source]! > countBySource[best]! ||
                  (countBySource[source] == countBySource[best] &&
                      kcalBySource[source]! > kcalBySource[best]!)));
      if (better) best = source;
    }
    return best;
  }

  /// Суммирует записи одного источника за день: калории всегда, макрос —
  /// сумма по записям, где он есть (`null`, если ни одна не отдаёт макрос).
  NutritionDay _sumNutrition(
    DateKey date,
    List<HealthDataPoint> points,
    DataSource source,
    String package,
  ) {
    var calories = 0.0;
    double? protein;
    double? fat;
    double? carbs;
    for (final p in points) {
      final v = _nutritionValue(p);
      calories += v.calories ?? 0;
      if (v.protein != null) protein = (protein ?? 0) + v.protein!;
      if (v.fat != null) fat = (fat ?? 0) + v.fat!;
      if (v.carbs != null) carbs = (carbs ?? 0) + v.carbs!;
    }
    return NutritionDay(
      date: date,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      source: source,
      sourcePackage: package,
    );
  }

  // ─── BASAL / HEIGHT: чтение HC-значений (Фаза 7, A.4) ──────────────────────

  /// HC `BASAL_ENERGY_BURNED` по дням: instant-записи, значение в ккал/день
  /// (`HealthDataConverter.kt`: `inKilocaloriesPerDay`), last-wins за день.
  Map<DateKey, double> resolveBasalForAllDates(List<HealthDataPoint> basalPoints) {
    final byDate = <DateKey, List<HealthDataPoint>>{};
    for (final p in basalPoints) {
      byDate.putIfAbsent(DateKey(p.dateFrom), () => []).add(p);
    }

    final result = <DateKey, double>{};
    for (final entry in byDate.entries) {
      result[entry.key] = _numericValue(_lastByTime(entry.value));
    }
    return result;
  }

  /// HC `HEIGHT` за диапазон: last-wins по времени записи → префилл профиля
  /// (рост меняется медленно, грузим за 365 дней).
  double? resolveHeight(List<HealthDataPoint> heightPoints) {
    if (heightPoints.isEmpty) return null;
    return _numericValue(_lastByTime(heightPoints));
  }

  // ─── Расход по дням: каскад BMR + 4 компонента (Фаза 7, A.4–A.5) ───────────

  /// Считает `ExpenditureDay` для каждого дня `[start, end]`, где рассчитан
  /// BMR (каскад A.4). День без BMR отсутствует в результате — баланс за него
  /// не считается. Синхронно, из резолвленных кешей, без сырых точек.
  ///
  /// Вес «на дату» — последняя резолвленная запись веса ≤ дата (префикс-проход
  /// по сортированному кешу). День без записи веса: шаги-компонент = 0,
  /// Mifflin невозможен (BMR из HC/ручной продолжает работать); силовые по MET
  /// тоже 0 (нужен вес), «своя ккал/сессия» работает без веса.
  ///
  /// [profile] — профиль с оверрайдами; рост уже смёржен с HC-префиллом
  /// вызывающим кодом (VM), здесь hc-префилла нет.
  Map<DateKey, ExpenditureDay> computeExpenditures({
    required Map<DateKey, WeightDay> weightCache,
    required Map<DateKey, StepsDay> stepsCache,
    required Map<DateKey, double> basalCache,
    required ExpenditureProfile profile,
    required DateKey start,
    required DateKey end,
  }) {
    final sortedWeights = weightCache.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final result = <DateKey, ExpenditureDay>{};
    var weightIdx = -1;
    double? weightOnDate;

    var day = start.value;
    while (!day.isAfter(end.value)) {
      final date = DateKey(day);

      while (weightIdx + 1 < sortedWeights.length &&
          !sortedWeights[weightIdx + 1].date.value.isAfter(date.value)) {
        weightIdx++;
        weightOnDate = sortedWeights[weightIdx].weight;
      }

      final bmr = _bmrForDate(
        date,
        basalCache: basalCache,
        profile: profile,
        weightKg: weightOnDate,
      );
      if (bmr != null) {
        final steps = stepsCache[date]?.steps ?? 0;
        final stepsKcal = weightOnDate == null
            ? 0.0
            : steps * weightOnDate * profile.stepsKcalPerKgPerStep;
        result[date] = ExpenditureDay(
          date: date,
          bmrKcal: bmr,
          stepsKcal: stepsKcal,
          trainingKcal: _trainingKcalPerDay(profile, weightOnDate),
          householdKcal: profile.householdKcal,
        );
      }

      day = day.add(const Duration(days: 1));
    }

    return result;
  }

  /// Каскад BMR (A.4): 1) ручной оверрайд (константа на все дни) →
  /// 2) HC `BASAL_ENERGY_BURNED` (last-wins за день) → 3) Mifflin-St Jeor
  /// (пол + возраст + рост + вес на дату; возраст = год даты − birth_year) →
  /// 4) `null` — расход за день «—», баланс не считается.
  ///
  /// Ручной режим с незаполненным значением трактуется как авто (защита от
  /// битых настроек).
  double? _bmrForDate(
    DateKey date, {
    required Map<DateKey, double> basalCache,
    required ExpenditureProfile profile,
    required double? weightKg,
  }) {
    if (profile.bmrMode == BmrMode.manual &&
        profile.bmrManualKcal != null &&
        profile.bmrManualKcal! > 0) {
      return profile.bmrManualKcal;
    }

    final hc = basalCache[date];
    if (hc != null && hc > 0) return hc;

    if (!profile.isCompleteForMifflin) return null;
    if (weightKg == null || weightKg <= 0) return null;
    return mifflinStJeor(
      sex: profile.sex!,
      weightKg: weightKg,
      heightCm: profile.heightCm!,
      ageYears: date.value.year - profile.birthYear!,
    );
  }

  /// Силовые (A.3): «своя ккал/сессия» × частота/7, иначе
  /// `(MET − 1) × вес × часы × частота / 7` (Compendium 3.5/6.0, нетто).
  double _trainingKcalPerDay(ExpenditureProfile profile, double? weightKg) {
    final freq = profile.trainingFreqPerWeek;
    if (freq <= 0) return 0;

    final own = profile.trainingKcalPerSession;
    if (own != null && own > 0) return own * freq / 7;

    if (weightKg == null || weightKg <= 0) return 0;
    final met = profile.trainingIntensity == TrainingIntensity.moderate
        ? ExpenditureConfig.trainingMetModerate
        : ExpenditureConfig.trainingMetHeavy;
    final hours = profile.trainingDurationMin / 60;
    return (met - ExpenditureConfig.trainingNetMetSubtraction) *
        weightKg *
        hours *
        freq /
        7;
  }

  // ─── Список найденных источников (C.1) ──────────────────────────────────────



  /// Уникальные пакеты внешних источников (наш пакет не входит — Tier 1
  /// всегда побеждает). Строится по сырым точкам сессии, без дополнительных
  /// запросов к Health Connect.
  List<String> externalSources(List<HealthDataPoint> points) {
    final sources = points
        .map(sourcePackageOf)
        .where((s) => s != appPackageId)
        .toSet();
    return sources.toList()..sort();
  }

  // ─── EMA (экспоненциальное сглаживание) ──────────────────────────────────────

  /// Пересчитывает EMA по всему кешу весов и возвращает новый кеш EMA.
  ///
  /// Алгоритм: стандартная EMA с множителем `2 / (period + 1)`.
  /// Первая точка инициализируется самим значением веса, далее каждая
  /// следующая точка: `ema = (weight - prevEma) * multiplier + prevEma`.
  ///
   /// Разрыв данных (2026-09-16): между соседними взвешиваниями
  /// [RecommendationConfig.emaBreakGapDays] (5) и более пустых дней — серия
  /// ОБРЫВАЕТСЯ: новое скользящее стартует заново (инициализация весом
  /// точки после разрыва), значение до разрыва не наследуется. Пропуски
  /// 1–4 дня EMA «тянет» через себя как обычно. На графике веса это разрыв
  /// линии на месте «пустот».
  ///
 /// Период [period] определяет сглаживание: больше период — сильнее сглаживание.
  /// EMA-точки не имеют отношения к приоритету источников, поэтому `source`
  /// устанавливается в [DataSource.external] (значение не используется
  /// потребителем), `sourcePackage` — `null`.
  ///
  /// ⚠️ Полный пересчёт при каждом вызове — известный TODO по производительности
  /// при данных за год+, принимается как есть (см. `systemPatterns.md`).
  Map<DateKey, WeightDay> computeEma(Map<DateKey, WeightDay> weightCache, int period) {
    if (weightCache.isEmpty) return {};

    final sorted = weightCache.values.toList()..sort((a, b) => a.date.compareTo(b.date));

    final multiplier = 2 / (period + 1);
    double ema = sorted.first.weight;

    final result = <WeightDay>[
      WeightDay(date: sorted.first.date, weight: ema, source: DataSource.external),
    ];
    for (int i = 1; i < sorted.length; i++) {
      final gapDays =
          sorted[i].date.value.difference(sorted[i - 1].date.value).inDays - 1;
      if (gapDays >= RecommendationConfig.emaBreakGapDays) {
        // Длительный разрыв: серия обрывается, скользящее стартует заново.
        ema = sorted[i].weight;
      } else {
        ema = (sorted[i].weight - ema) * multiplier + ema;
      }
      result.add(WeightDay(date: sorted[i].date, weight: ema, source: DataSource.external));
    }

    return Map.fromEntries(result.map((e) => MapEntry(e.date, e)));
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  /// Tier 2-пул точек дня: не наши, не отклонённые, при выбранном источнике —
  /// только его точки (C.2, шаги 1–2).
  List<HealthDataPoint> _tier2Pool(
    List<HealthDataPoint> dayPoints,
    Map<String, ConfirmDecision> decisions,
    SourceSelection selection,
  ) {
    final notRefused = dayPoints.where((p) {
      if (isOurPoint(p)) return false;
      return decisions[sourcePackageOf(p)] != ConfirmDecision.refused;
    });
    if (!selection.isAuto) {
      return notRefused
          .where((p) => sourcePackageOf(p) == selection.package)
          .toList();
    }
    return notRefused.toList();
  }

  /// Возвращает точку с последним `dateFrom` (last-wins).
  HealthDataPoint _lastByTime(List<HealthDataPoint> points) {
    final sorted = [...points]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    return sorted.last;
  }

  /// Извлекает числовое значение из [NumericHealthValue].
  double _numericValue(HealthDataPoint point) {
    final v = point.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    throw StateError('Expected NumericHealthValue, got ${v.runtimeType}');
  }

  /// Извлекает питание из [NutritionHealthValue].
  NutritionHealthValue _nutritionValue(HealthDataPoint point) {
    final v = point.value;
    if (v is NutritionHealthValue) return v;
    throw StateError('Expected NutritionHealthValue, got ${v.runtimeType}');
  }
}