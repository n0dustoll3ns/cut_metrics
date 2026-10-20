import 'package:cut_metrics/domain/calc_trace.dart';
import 'package:cut_metrics/domain/calc_trace_builders.dart';
import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/recommendation_engine.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/domain/sleep_day.dart';
import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/domain/weekly_energy_stats.dart';
import 'package:cut_metrics/repo/mock_health_repository.dart';
import 'package:cut_metrics/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Тесты билдеров трасс «Как рассчитано» (CalcDetail §3).
///
/// ГЛАВНЫЙ инвариант каждого теста: итог трассы == числу на экране, т.е.
/// значению из существующих функций домена (`resolve*`, `computeExpenditures`,
/// `computeEma`, `computeEnergyStats`, `RecommendationEngine.compute`).
void main() {
  final mock = MockHealthRepository();
  final processor = HealthDataProcessor(appPackageId: kAppPackageId);

  final d = DateKey(DateTime(2026, 1, 15));
  final today = DateTime(2026, 1, 16);

  Future<List<HealthDataPoint>> load(HealthDataType type, DateTime start, DateTime end) =>
      mock.fetchRawData(types: [type], startDate: start, endDate: end);

  setUp(mock.clear);

  // ==========================================================================
  // §3.1 stepsDayTrace
  // ==========================================================================
  group('stepsDayTrace', () {
    final rangeStart = DateTime(2026, 1, 1);
    final rangeEnd = DateTime(2026, 1, 31);

    test('«Авто»: победитель с максимальной суммой, конкурент «сумма меньше»', () async {
      mock.addExternalSteps(d.value, 2000, sourcePackage: 'com.samsung.health');
      mock.addExternalSteps(d.value, 4500, sourcePackage: 'com.samsung.health');
      mock.addExternalSteps(d.value, 1500, sourcePackage: 'com.samsung.health');
      mock.addExternalSteps(d.value, 6000, sourcePackage: 'com.google.fit');

      final points = await load(HealthDataType.STEPS, rangeStart, rangeEnd);
      final day = processor.resolveStepsForDate(d, points);

      final trace = stepsDayTrace(
        processor: processor,
        date: d,
        day: day,
        rawStepsPoints: points,
        decisions: const {},
        selection: const SourceSelection.auto(),
      );

      // Итог трассы == StepsDay.steps (формат экрана).
      expect(trace.resultText, formatThousands(day!.steps));
      expect(trace.resultText, '8 000');
      expect(trace.resultUnit, 'шагов');

      // Сравнение сумм в шаге 1.
      expect(trace.steps[0].formulaText, '8 000 > 6 000');
      expect(trace.steps[0].resultText, contains('com.samsung.health'));

      // Записи победителя в recordsText и в шаге 2.
      expect(trace.inputs.first.recordsText, '2 000 + 4 500 + 1 500');
      expect(trace.steps[1].formulaText, '2 000 + 4 500 + 1 500');
      expect(trace.steps[1].resultText, '= 8 000');
      expect(trace.steps[1].note, contains('агрегат Health Connect не используется'));

      // Конкурент скрыт за чекбоксом с причиной.
      final loser = trace.inputs.where((i) => i.notUsed).single;
      expect(loser.notUsedReason, 'сумма меньше');
      expect(loser.valueText, '6 000');
    });

    test('ручная запись (Tier 1) побеждает', () async {
      mock.addManualSteps(d.value, 5000);
      mock.addExternalSteps(d.value, 9000, sourcePackage: 'com.samsung.health');

      final points = await load(HealthDataType.STEPS, rangeStart, rangeEnd);
      final day = processor.resolveStepsForDate(d, points);

      final trace = stepsDayTrace(
        processor: processor,
        date: d,
        day: day,
        rawStepsPoints: points,
        decisions: const {},
        selection: const SourceSelection.auto(),
      );

      expect(day!.source, DataSource.manual);
      expect(trace.resultText, '5 000');
      expect(trace.inputs.first.kind, TraceSourceKind.manual);
      expect(trace.inputs.where((i) => i.notUsed).single.notUsedReason,
          'ручная запись побеждает');
    });

    test('отклонённый источник — «источник отклонён»', () async {
      mock.addExternalSteps(d.value, 8000, sourcePackage: 'com.samsung.health');
      mock.addExternalSteps(d.value, 3000, sourcePackage: 'com.bad.app');

      final points = await load(HealthDataType.STEPS, rangeStart, rangeEnd);
      final day = processor.resolveStepsForDate(
        d,
        points,
        decisions: const {'com.bad.app': ConfirmDecision.refused},
      );

      final trace = stepsDayTrace(
        processor: processor,
        date: d,
        day: day,
        rawStepsPoints: points,
        decisions: const {'com.bad.app': ConfirmDecision.refused},
        selection: const SourceSelection.auto(),
      );

      expect(trace.resultText, '8 000');
      expect(trace.inputs.where((i) => i.notUsed).single.notUsedReason,
          'источник отклонён');
    });

    test('данных нет → итог «—» без расчёта', () async {
      final points = await load(HealthDataType.STEPS, rangeStart, rangeEnd);
      final trace = stepsDayTrace(
        processor: processor,
        date: d,
        day: null,
        rawStepsPoints: points,
        decisions: const {},
        selection: const SourceSelection.auto(),
      );
      expect(trace.resultText, '—');
      expect(trace.inputs, isEmpty);
    });
  });

  // ==========================================================================
  // §3.2 nutritionDayTrace
  // ==========================================================================
  group('nutritionDayTrace', () {
    final rangeStart = DateTime(2026, 1, 1);
    final rangeEnd = DateTime(2026, 1, 31);

    test('«Авто» по покрытию дней: A — 3 дн., B — 2 → A; итог == calories', () async {
      // A (дефолт kNutritionSourceId) покрывает 10, 11, 12, 15 января;
      // B (fatsecret) — 13, 14, 15.
      for (final day in [10, 11, 12]) {
        mock.addExternalNutrition(DateTime(2026, 1, day),
            calories: 2000, protein: 100, fat: 50, carbs: 200);
      }
      mock.addExternalNutrition(d.value,
          calories: 2000, protein: 100, fat: 50, carbs: 200);
      // B покрывает 13 и 14 января (2 дня против 3 у A).
      mock.addExternalNutrition(DateTime(2026, 1, 13),
          calories: 1800, sourcePackage: 'com.fatsecret');
      mock.addExternalNutrition(DateTime(2026, 1, 14),
          calories: 1900, sourcePackage: 'com.fatsecret');
      mock.addExternalNutrition(d.value,
          calories: 1500, sourcePackage: 'com.fatsecret');

      final points = await load(HealthDataType.NUTRITION, rangeStart, rangeEnd);
      final day = processor.resolveNutritionForAllDates(points)[d];

      final trace = nutritionDayTrace(
        processor: processor,
        date: d,
        day: day,
        rawNutritionPoints: points,
        decisions: const {},
        selection: const SourceSelection.auto(),
      );

      expect(day!.sourcePackage, kNutritionSourceId);
      expect(trace.resultText, formatThousands(day.calories));
      expect(trace.resultText, '2 000');
      expect(trace.resultUnit, 'ккал');
      expect(trace.resultNote, '100 / 50 / 200 г (Б/Ж/У)');

      // Шаг авто-правила показывает покрытие дней.
      final autoStep = trace.steps.first;
      expect(autoStep.title, contains('покрытие дней'));
      expect(autoStep.formulaText, contains('4 дн.'));
      expect(autoStep.resultText, contains(kNutritionSourceId));

      // Конкурент — «меньше покрытие дней».
      final loser = trace.inputs.where((i) => i.notUsed).single;
      expect(loser.notUsedReason, 'меньше покрытие дней');
      expect(loser.valueText, '5 200'); // сумма ккал B за диапазон
      expect(loser.note, contains('3 дн.'));
    });

    test('ручной «Итог дня» (Tier 1) побеждает', () async {
      mock.addManualNutrition(d.value,
          calories: 2500, protein: 150, fat: 70, carbs: 220);
      mock.addExternalNutrition(d.value, calories: 3000);

      final points = await load(HealthDataType.NUTRITION, rangeStart, rangeEnd);
      final day = processor.resolveNutritionForAllDates(points)[d];

      final trace = nutritionDayTrace(
        processor: processor,
        date: d,
        day: day,
        rawNutritionPoints: points,
        decisions: const {},
        selection: const SourceSelection.auto(),
      );

      expect(day!.source, DataSource.manual);
      expect(trace.resultText, '2 500');
      expect(trace.inputs.first.kind, TraceSourceKind.manual);
      expect(trace.inputs.where((i) => i.notUsed).single.notUsedReason,
          'ручная запись побеждает');
    });
  });


  // ==========================================================================
  // §3.3 expenditureDayTrace / expenditureComponentTrace
  // ==========================================================================
  group('expenditureTrace', () {
    Map<DateKey, WeightDay> weightCache(double weight) => {
          DateKey(DateTime(2026, 1, 10)): WeightDay(
              date: DateKey(DateTime(2026, 1, 10)),
              weight: weight,
              source: DataSource.external,
              sourcePackage: 'com.samsung.health'),
        };

    test('HC BASAL побеждает в каскаде; итог == ExpenditureDay.total', () {
      final weights = weightCache(84.2);
      final steps = {
        d: StepsDay(date: d, steps: 12400, source: DataSource.external),
      };
      final basal = {d: 1670.0};
      final day = processor.computeExpenditures(
        weightCache: weights,
        stepsCache: steps,
        basalCache: basal,
        profile: const ExpenditureProfile(),
        start: d,
        end: d,
      )[d]!;

      final trace = expenditureDayTrace(
        processor: processor,
        date: d,
        day: day,
        weightCache: weights,
        stepsCache: steps,
        basalCache: basal,
        profile: const ExpenditureProfile(),
      );

      expect(trace.resultText, '≈ ${formatThousands(day.total)}');
      expect(trace.resultUnit, 'ккал/день');
      // Каскад остановился на HC BASAL.
      expect(trace.steps.first.formulaText, contains('HC BASAL за день: 1 670'));
      expect(trace.steps.first.resultText, '1 670 ✓');
      // Шаги: подстановка 12 400 × 84.2 × 0.0004.
      expect(trace.steps[1].formulaText,
          '12 400 × 84.2 × ${ExpenditureConfig.defaultStepsKcalPerKgPerStep}');
      // Последний шаг — сумма 4 компонентов.
      expect(trace.steps.last.title, contains('Сумма компонентов'));
    });

    test('Mifflin: полный профиль, BASAL нет — формула с подстановкой', () {
      final weights = weightCache(84.2);
      final profile = const ExpenditureProfile(
        sex: EnergySex.male,
        birthYear: 1990,
        heightCm: 178,
      );
      final day = processor.computeExpenditures(
        weightCache: weights,
        stepsCache: const {},
        basalCache: const {},
        profile: profile,
        start: d,
        end: d,
      )[d]!;

      // Mifflin: 10×84.2 + 6.25×178 − 5×36 + 5 = 1 779.5.
      expect(day.bmrKcal, closeTo(1779.5, 0.01));

      final trace = expenditureDayTrace(
        processor: processor,
        date: d,
        day: day,
        weightCache: weights,
        stepsCache: const {},
        basalCache: const {},
        profile: profile,
      );

      final cascade = trace.steps.first;
      expect(cascade.formulaText,
          contains('Mifflin: 10.0×84.2 + 6.25×178 − 5.0×36 + 5.0'));
      expect(cascade.resultText, contains('= ${formatThousands(day.bmrKcal)}'));
      expect(cascade.note, contains('ручной ввод'));
      expect(trace.resultText, '≈ ${formatThousands(day.total)}');
    });

    test('профиль неполон → «расход не рассчитан»', () {
      final trace = expenditureDayTrace(
        processor: processor,
        date: d,
        day: null,
        weightCache: weightCache(84.2),
        stepsCache: const {},
        basalCache: const {},
        profile: const ExpenditureProfile(),
      );

      expect(trace.resultText, '—');
      expect(trace.steps.first.resultText, contains('профиль неполон'));
      expect(trace.resultNote, contains('BMR не рассчитан'));
    });

    test('компонент «шаги»: итог == ExpenditureDay.stepsKcal, один шаг', () {
      final weights = weightCache(84.2);
      final steps = {d: StepsDay(date: d, steps: 12400, source: DataSource.external)};
      final day = processor.computeExpenditures(
        weightCache: weights,
        stepsCache: steps,
        basalCache: {d: 1670.0},
        profile: const ExpenditureProfile(),
        start: d,
        end: d,
      )[d]!;

      final trace = expenditureComponentTrace(
        processor: processor,
        date: d,
        day: day,
        weightCache: weights,
        stepsCache: steps,
        basalCache: {d: 1670.0},
        profile: const ExpenditureProfile(),
        component: ExpenditureComponent.steps,
      );

      expect(trace.title, 'Расход: Шаги');
      expect(trace.resultText, '≈ ${formatThousands(day.stepsKcal)}');
      expect(trace.steps, hasLength(1));
    });

    test('силовые: MET-режим с подстановкой параметров', () {
      final weights = weightCache(84.2);
      final profile = const ExpenditureProfile(
        trainingFreqPerWeek: 3,
        trainingDurationMin: 60,
        trainingIntensity: TrainingIntensity.moderate,
      );
      final day = processor.computeExpenditures(
        weightCache: weights,
        stepsCache: const {},
        basalCache: {d: 1670.0},
        profile: profile,
        start: d,
        end: d,
      )[d]!;

      final trace = expenditureComponentTrace(
        processor: processor,
        date: d,
        day: day,
        weightCache: weights,
        stepsCache: const {},
        basalCache: {d: 1670.0},
        profile: profile,
        component: ExpenditureComponent.training,
      );

      expect(trace.steps.first.formulaText, '(3.5 − 1) × 84.2 × 1 ч × 3 / 7');
      expect(trace.resultText, '≈ ${formatThousands(day.trainingKcal)}');
    });
  });


  // ==========================================================================
  // §3.4 balanceDayTrace
  // ==========================================================================
  group('balanceDayTrace', () {
    test('итог == EnergyBalanceDay.balance; целевая линия в resultNote', () {
      final intake = NutritionDay(
          date: d, calories: 2100, source: DataSource.external);
      final out = ExpenditureDay(
          date: d,
          bmrKcal: 2000,
          stepsKcal: 200,
          trainingKcal: 100,
          householdKcal: 50);
      final weight = WeightDay(date: d, weight: 84.2, source: DataSource.external);

      final trace = balanceDayTrace(
        date: d,
        intake: intake,
        out: out,
        latestWeight: weight,
        targetPacePercent: 0.8,
      );

      final balance = EnergyBalanceDay(intake: intake, out: out).balance;
      expect(trace.resultText, formatSignedKcal(balance));
      expect(trace.resultText, '−250');

      // Цель = 84.2 × 0.8 × 11 = 740.96 → округление до 10 → 740.
      expect(trace.resultNote, contains('84.2 × 0.8 × 11'));
      expect(trace.resultNote, contains('−740'));
      expect(trace.steps.first.formulaText, '2 100 − 2 350');
    });

    test('расхода нет → «баланс не считается»', () {
      final trace = balanceDayTrace(
        date: d,
        intake: NutritionDay(date: d, calories: 2100, source: DataSource.external),
        out: null,
        latestWeight: null,
        targetPacePercent: 0.8,
      );
      expect(trace.resultText, '—');
      expect(trace.steps.first.resultText, 'баланс не считается');
      expect(trace.steps.first.note, contains('BMR'));
    });
  });


  // ==========================================================================
  // §3.5 Среднесуточные (Тренд)
  // ==========================================================================
  group('avgWithTrace', () {
    DateKey day(int offset) => DateKey(today.subtract(Duration(days: offset)));

    test('avgStepsWithTrace == геттер avgSteps (round, без «сегодня»)', () {
      // day(0) — сегодня (исключён), дни 1..6 — в расчёт.
      final values = [99999, 6000, 7000, 8000, 9000, 8620, 9000];
      final cache = <DateKey, StepsDay>{
        for (final (i, s) in values.indexed)
          day(i): StepsDay(date: day(i), steps: s, source: DataSource.external),
      };
      final start = today.subtract(const Duration(days: 6));
      final result = avgStepsWithTrace(
        stepsCache: cache,
        start: start,
        end: today,
        today: today,
        rangeDays: 7,
      );

      // Вручную как в VM: дни 1..6 (сегодня = 0 исключён), среднее round.
      final avg = ((6000 + 7000 + 8000 + 9000 + 8620 + 9000) / 6).round();
      expect(result.value, avg);
      expect(result.trace.resultText, formatThousands(avg));

      // Таблица дней, покрытие, не свёрнуто на 7 днях.
      expect(result.trace.dayRows, hasLength(6));
      expect(result.trace.resultNote, 'по 6 дн.');
      expect(result.trace.dayRowsCollapsedByDefault, isFalse);

      // Скелет: отсечение → сумма → среднее.
      expect(result.trace.steps.first.title, contains('Отсечение'));
      expect(result.trace.steps.last.title, contains('Среднее'));
    });

    test('отсечение по 5+-дневному разрыву (окно 30 дней)', () {
      // Дни 27..26 назад, затем разрыв, дни 5..1 назад.
      final cache = <DateKey, StepsDay>{
        day(27): StepsDay(date: day(27), steps: 9999, source: DataSource.external),
        day(26): StepsDay(date: day(26), steps: 8888, source: DataSource.external),
        day(5): StepsDay(date: day(5), steps: 6000, source: DataSource.external),
        day(1): StepsDay(date: day(1), steps: 8000, source: DataSource.external),
      };
      final result = avgStepsWithTrace(
        stepsCache: cache,
        start: today.subtract(const Duration(days: 29)),
        end: today,
        today: today,
        rangeDays: 30,
      );

      expect(result.value, 7000); // только дни после разрыва
      expect(result.trace.steps.first.resultText, contains('отсечено 2 дн.'));
      expect(result.trace.dayRows, hasLength(2));
    });

    test('90 дней → таблица свёрнута по умолчанию', () {
      final result = avgStepsWithTrace(
        stepsCache: const {},
        start: today.subtract(const Duration(days: 89)),
        end: today,
        today: today,
        rangeDays: 90,
      );
      expect(result.value, isNull);
      expect(result.trace.dayRowsCollapsedByDefault, isTrue);
    });

    test('avgSleepWithTrace: значение == сумма total / ночей, 1 знак', () {
      final cache = <DateKey, SleepDay>{
        day(2): SleepDay(date: day(2), deep: 0, light: 0, rem: 0, asleep: 7.5),
        day(1): SleepDay(date: day(1), deep: 6, light: 1, rem: 1, asleep: 0),
      };

      final result = avgSleepWithTrace(
        sleepCache: cache,
        start: today.subtract(const Duration(days: 6)),
        end: today,
        rangeDays: 7,
      );

      expect(result.value, closeTo(7.75, 0.001));
      expect(result.trace.resultText, '7.8');
      expect(result.trace.dayRows!.map((r) => r.valueText), ['7.5 ч', '8.0 ч']);
    });

    test('avgIntakeWithTrace и avgMacrosWithTrace — по дням с приходом', () {
      final cache = <DateKey, NutritionDay>{
        day(3): NutritionDay(
            date: day(3), calories: 2000, protein: 100, fat: 50, carbs: 200, source: DataSource.external),
        day(2): NutritionDay(
            date: day(2), calories: 2200, fat: 90, source: DataSource.external),
        day(0): NutritionDay(
            date: day(0), calories: 99999, source: DataSource.external), // сегодня — вне
      };
      final start = today.subtract(const Duration(days: 6));

      final intake = avgIntakeWithTrace(
        nutritionCache: cache, start: start, end: today, today: today, rangeDays: 7);
      expect(intake.value, 2100);
      expect(intake.trace.resultText, '2 100');

      final macros = avgMacrosWithTrace(
        nutritionCache: cache, start: start, end: today, today: today, rangeDays: 7);
      expect(macros.protein, 50); // 100 + 0 (день без белка = 0)
      expect(macros.fat, 70);
      expect(macros.carbs, 100);
      expect(macros.trace.resultText, '50 / 70 / 100');
      expect(macros.trace.resultNote, contains('день без макроса = 0'));
    });

    test('avgExpenditureWithTrace: знаменатель — дни с BMR', () {
      final cache = <DateKey, ExpenditureDay>{
        day(2): ExpenditureDay(
            date: day(2), bmrKcal: 2000, stepsKcal: 0, trainingKcal: 0, householdKcal: 200),
        day(1): ExpenditureDay(
            date: day(1), bmrKcal: 1800, stepsKcal: 100, trainingKcal: 0, householdKcal: 200),
      };
      final result = avgExpenditureWithTrace(
        expenditureCache: cache,
        start: today.subtract(const Duration(days: 6)),
        end: today,
        today: today,
        rangeDays: 7,
      );

      expect(result.value, 2150);
      expect(result.trace.resultText, '≈ ${formatThousands(2150)}');
      expect(result.trace.resultNote, 'по 2 дн.');
    });
  });


  // ==========================================================================
  // §3.6 paceTrace
  // ==========================================================================
  group('paceTrace', () {
    /// 7 взвешиваний 10..16 января с падением ~0.1 кг/день.
    Map<DateKey, WeightDay> weights() => {
          for (var i = 0; i < 7; i++)
            DateKey(DateTime(2026, 1, 10 + i)): WeightDay(
                date: DateKey(DateTime(2026, 1, 10 + i)),
                weight: 84.0 - 0.1 * i,
                source: DataSource.external),
        };

    test('итог == формату экрана `_paceValue`; emaRows == computeEma', () {
      final cache = weights();
      final ema =
          processor.computeEma(cache, RecommendationConfig.engineEmaPeriod);
      final summary = RecommendationEngine.compute(
        weightCache: cache,
        emaCache: ema,
        today: today,
        targetPacePercent: 0.8,
      );

      final trace = paceTrace(
        weightCache: cache,
        engineEmaCache: ema,
        today: today,
        targetPacePercent: 0.8,
        summary: summary,
      );

      expect(summary, isNotNull);
      final v = summary!.actualPacePercent;
      final sign = v < 0 ? '−' : '+';
      expect(trace.resultText, '$sign${v.abs().toStringAsFixed(1)}%');
      expect(trace.resultUnit, '%/нед');
      expect(trace.resultNote, contains('кг за неделю'));

      // Цепочка EMA: значения из computeEma, рестарты не помечены (разрывов нет).
      expect(trace.emaRows, hasLength(7));
      final sorted = ema.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      for (final (i, row) in trace.emaRows!.indexed) {
        expect(row.ema, closeTo(sorted[i].weight, 1e-9));
        expect(row.rawWeight, closeTo(cache[sorted[i].date]!.weight, 1e-9));
        expect(row.seriesRestart, isFalse);
      }

      // Шаги: точки → процент → нормализация → кг → статус.
      expect(trace.steps[1].title, contains('Процент изменения'));
      expect(trace.steps[2].title, contains('Нормализация'));
      expect(trace.steps[4].title, contains('Статус'));
    });

    test('данных недостаточно (<5 точек) → трасса-объяснение', () {
      final cache = {
        DateKey(DateTime(2026, 1, 14)): WeightDay(
            date: DateKey(DateTime(2026, 1, 14)),
            weight: 84,
            source: DataSource.external),
        DateKey(DateTime(2026, 1, 15)): WeightDay(
            date: DateKey(DateTime(2026, 1, 15)),
            weight: 83.9,
            source: DataSource.external),
      };
      final ema =
          processor.computeEma(cache, RecommendationConfig.engineEmaPeriod);
      final summary = RecommendationEngine.compute(
          weightCache: cache, emaCache: ema, today: today, targetPacePercent: 0.8);
      expect(summary, isNull);

      final trace = paceTrace(
          weightCache: cache,
          engineEmaCache: ema,
          today: today,
          targetPacePercent: 0.8,
          summary: summary);
      expect(trace.resultText, 'данных недостаточно');
      expect(trace.steps.first.resultText,
          contains('< ${RecommendationConfig.minWeightPointsInWindow}'));
    });

    test('разрыв 5+ дней → рестарт серии в цепочке EMA', () {
      final cache = {
        DateKey(DateTime(2026, 1, 1)): WeightDay(
            date: DateKey(DateTime(2026, 1, 1)),
            weight: 85.0,
            source: DataSource.external),
        // 2–6 января пусто — разрыв обрывает серию.
        DateKey(DateTime(2026, 1, 7)): WeightDay(
            date: DateKey(DateTime(2026, 1, 7)),
            weight: 84.0,
            source: DataSource.external),
      };
      final ema = processor.computeEma(cache, 7);
      final trace = paceTrace(
          weightCache: cache,
          engineEmaCache: ema,
          today: today,
          targetPacePercent: 0.8,
          summary: null);
      expect(trace.emaRows!.last.seriesRestart, isTrue);
      // После рестарта EMA == весу точки (как в computeEma).
      expect(trace.emaRows!.last.ema, closeTo(84.0, 1e-9));
    });
  });


  // ==========================================================================
  // §3.7 energyWeekTrace
  // ==========================================================================
  group('energyWeekTrace', () {
    test('итоги == WeeklyEnergyStats; день без расхода — «не считается»', () {
      final stats = computeEnergyStats(
        nutritionCache: {
          for (final i in [1, 2, 3])
            DateKey(today.subtract(Duration(days: i))): NutritionDay(
                date: DateKey(today.subtract(Duration(days: i))),
                calories: 2000,
                source: DataSource.external),
        },
        expenditureCache: {
          // Расход есть только в дни 1 и 2.
          for (final i in [1, 2])
            DateKey(today.subtract(Duration(days: i))): ExpenditureDay(
                date: DateKey(today.subtract(Duration(days: i))),
                bmrKcal: 2200,
                stepsKcal: 150,
                trainingKcal: 0,
                householdKcal: 200),
        },
        today: today,
      )!;

      final trace = energyWeekTrace(stats: stats, today: today);

      expect(trace.resultText, formatSignedKcal(stats.avgBalance!));
      expect(trace.resultNote, contains('приход 2 000'));
      expect(trace.resultNote, contains('расход ≈ 2 550'));

      // Ожидаемый темп = −550 × 7 / 7700 = −0.5 кг/нед.
      expect(stats.expectedKgPerWeek, closeTo(-0.5, 0.001));
      expect(trace.resultNote, contains('−0.50 кг/нед'));

      // Таблица: день 3 без расхода → «не считается».
      expect(trace.dayRows, hasLength(3));
      final noExp = trace.dayRows!.firstWhere((r) => r.value2Text == '—');
      expect(noExp.value3Text, 'не считается');

      // 4 шага: приход, расход, баланс, ожидание.
      expect(trace.steps.map((s) => s.title), contains(contains('Ожидаемый темп')));
    });

    test('stats == null → объяснение «данных питания < 2 дней»', () {
      final trace = energyWeekTrace(stats: null, today: today);
      expect(trace.resultText, '—');
      expect(trace.steps.first.resultText, contains('Фазы 5'));
    });
  });


  // ==========================================================================
  // §3.8 recommendationTrace
  // ==========================================================================
  group('recommendationTrace', () {
    Map<DateKey, WeightDay> weights() => {
          for (var i = 0; i < 7; i++)
            DateKey(DateTime(2026, 1, 10 + i)): WeightDay(
                date: DateKey(DateTime(2026, 1, 10 + i)),
                weight: 84.0 - 0.1 * i,
                source: DataSource.external),
        };

    WeeklyEnergyStats? stats() => computeEnergyStats(
          nutritionCache: {
            for (final i in [1, 2, 3])
              DateKey(today.subtract(Duration(days: i))): NutritionDay(
                  date: DateKey(today.subtract(Duration(days: i))),
                  calories: 2000,
                  source: DataSource.external),
          },
          expenditureCache: {
            for (final i in [1, 2])
              DateKey(today.subtract(Duration(days: i))): ExpenditureDay(
                  date: DateKey(today.subtract(Duration(days: i))),
                  bmrKcal: 2200,
                  stepsKcal: 150,
                  trainingKcal: 0,
                  householdKcal: 200),
          },
          today: today,
        );

    test('v2: итог == recommendationText дословно; шаги дельты', () {
      final cache = weights();
      final ema =
          processor.computeEma(cache, RecommendationConfig.engineEmaPeriod);
      final s = stats();
      final summary = RecommendationEngine.compute(
        weightCache: cache,
        emaCache: ema,
        today: today,
        targetPacePercent: 0.8,
        energyStats: s,
      )!;

      final trace =
          recommendationTrace(summary: summary, energyStats: s, weightKg: 83.4);

      expect(trace.resultText, summary.recommendationText);
      // Шаги дельты: raw → коридор → округление → новый приход → шаблон.
      expect(trace.steps[0].title, contains('× 11'));
      expect(trace.steps[1].title, contains('Коридор 50–300'));
      expect(trace.steps[2].title, contains('Округление до 10'));
      expect(trace.steps[3].title, contains('Новый приход'));
      expect(trace.steps.last.resultText, summary.recommendationText);
    });

    test('без энергостатов — ветка Фазы 5, итог дословно', () {
      final cache = weights();
      final ema =
          processor.computeEma(cache, RecommendationConfig.engineEmaPeriod);
      final summary = RecommendationEngine.compute(
          weightCache: cache, emaCache: ema, today: today, targetPacePercent: 0.8)!;

      final trace =
          recommendationTrace(summary: summary, energyStats: null, weightKg: 83.4);

      expect(trace.resultText, summary.recommendationText);
      expect(trace.steps.first.title, contains('Энергостаты недоступны'));
      expect(trace.steps.last.title, contains('Шаблон Фазы 5'));
    });
  });

  // ==========================================================================
  // §3.9 smoothedWeightTrace
  // ==========================================================================
  group('smoothedWeightTrace', () {
    test('итог == smoothedWeightToday (1 знак); цепочка из той же EMA', () {
      final cache = {
        for (var i = 0; i < 7; i++)
          DateKey(DateTime(2026, 1, 10 + i)): WeightDay(
              date: DateKey(DateTime(2026, 1, 10 + i)),
              weight: 84.0 - 0.1 * i,
              source: DataSource.external),
      };
      final ema = processor.computeEma(cache, 3);
      final sorted = ema.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      final trace = smoothedWeightTrace(
        smoothedWeight: sorted.last.weight,
        emaPeriod: 3,
        weightCache: cache,
        emaCache: ema,
      );

      expect(trace.resultText, sorted.last.weight.toStringAsFixed(1));
      expect(trace.resultUnit, 'кг');
      expect(trace.steps.first.title, contains('последняя точка EMA-линии'));
      expect(trace.steps.first.note, contains('k = 2 / (3 + 1) = 0.500'));
      expect(trace.emaRows, hasLength(7));
      expect(trace.inputs.first.label, contains('16 января'));
    });

    test('данных нет → «—»', () {
      final trace = smoothedWeightTrace(
          smoothedWeight: null, emaPeriod: 3, weightCache: const {}, emaCache: const {});
      expect(trace.resultText, '—');
    });
  });
}

