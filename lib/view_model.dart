import 'dart:async';
import 'package:collection/collection.dart';
import 'package:cut_metrics/domain/date_extension.dart';
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:cut_metrics/domain.dart';
import '../repo/health.dart';
import '../domain/weight.dart';
import '../domain/nutrition.dart';
import '../domain/sleep.dart';

/// Единая ViewModel для всего дашборда.
/// Собирает всю логику по загрузке и обработке данных из Google Health.
class ViewModel extends ChangeNotifier {
  final HealthRepository repo;
  final SleepAnalyzer _sleepAnalyzer;
  static const sleepDataTypes = [
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
  ];
  static const weightDataTypes = [HealthDataType.WEIGHT];
  static const nutritionDataTypes = [HealthDataType.NUTRITION];
  static const stepsDataTypes = [HealthDataType.STEPS];
  static const allDataTypes = [
    ...sleepDataTypes,
    ...weightDataTypes,
    ...nutritionDataTypes,
    ...stepsDataTypes,
  ];

  // Геттеры
  List<WeightDay> get weightData => _weightData;
  List<WeightDay> get emaData => _emaData;
  List<NutritionDay> get nutritionData => _nutritionData;
  List<SleepDay> get sleepData => _sleepData;
  List<StepsDay> get stepsData => _stepsData;
  DateTime get start => _start;
  DateTime get end => _end;
  int get selectedDurationInDays => _end.difference(_start).inDays;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ViewModel({required HealthRepository repository, SleepAnalyzer? sleepAnalyzer})
    : repo = repository,
      _sleepAnalyzer = sleepAnalyzer ?? SleepAnalyzer() {
    _init();
  }

  // Состояние
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  bool _isLoading = false;
  String? _error;

  // Кеш для графиков
  Map<DateKey, WeightDay> _weightCache = {};
  Map<DateKey, WeightDay> _emaCache = {};
  Map<DateKey, NutritionDay> _nutritionCache = {};
  Map<DateKey, SleepDay> _sleepCache = {};
  Map<DateKey, StepsDay> _stepsCache = {};

  // Данные для графиков
  List<WeightDay> _weightData = [];
  List<WeightDay> _emaData = [];
  List<NutritionDay> _nutritionData = [];
  List<SleepDay> _sleepData = [];
  List<StepsDay> _stepsData = [];

  /// Инициализация
  void _init() async {
    await setDate(start: DateTime.now().subtract(Duration(days: 30)), end: DateTime.now());
    await setDate(start: DateTime.now().subtract(Duration(days: 7)), end: DateTime.now());
  }

  DateTimeRange? get unloadedInterval {
    DateKey currentLatestStart = [
      _weightCache.keys.earliestDate,
      _emaCache.keys.earliestDate,
      _nutritionCache.keys.earliestDate,
      _sleepCache.keys.earliestDate,
      _stepsCache.keys.earliestDate,
    ].latestDate;
    DateKey currentEarliestEnd = [
      _weightCache.keys.latestDate,
      _emaCache.keys.latestDate,
      _nutritionCache.keys.latestDate,
      _sleepCache.keys.latestDate,
      _stepsCache.keys.latestDate,
    ].earliestDate;

    final currentLoadedInterval = DateTimeRange(
      start: currentLatestStart.value,
      end: currentEarliestEnd.value,
    );

    final targetInterval = DateTimeRange(start: _start, end: _end);

    return targetInterval.getUncoveredRange(currentLoadedInterval);
  }

  /// Запрос прав и загрузка всех данных
  Future<void> loadData() async {
    //TODO добавить загрузку данных с разных дат
    _isLoading = true;
    _error = null;
    notifyListeners();

    final interval = unloadedInterval;

    if (interval == null) return;

    try {
      // Запрашиваем права на все типы данных сразу

      bool granted = await repo.checkAndRequestPermissions(allDataTypes);
      if (!granted) {
        _error = "Permission denied or SDK unavailable";
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Загружаем все данные

      final (weightPoints, nutritionPoints, activityPoints, sleepPoints) = (
        await repo.fetchRawData(types: weightDataTypes, startDate: interval.start, endDate: interval.end),
        await repo.fetchRawData(types: nutritionDataTypes, startDate: interval.start, endDate: interval.end),
        await repo.fetchRawData(types: stepsDataTypes, startDate: interval.start, endDate: interval.end),
        await repo.fetchRawData(types: sleepDataTypes, startDate: interval.start, endDate: interval.end),
      );

      // Обрабатываем вес с EMA
      _processWeightData(weightPoints);
      _processEMA(_weightData, _emaPeriod);

      // Обрабатываем энергобаланс
      // _processEnergyBalanceData(nutritionPoints, _end);

      // Обрабатываем сон через SleepAnalyzer
      _sleepData = _sleepAnalyzer.processSleepData(
        rawPoints: sleepPoints,
        daysToAnalyze: selectedDurationInDays,
        now: _end,
      );

      // Обрабатываем шаги
      _stepsData = _processStepsData(activityPoints);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = "Failed to load  $e";
      _isLoading = false;
      notifyListeners();
      debugPrint("Dashboard Error: $e");
    }
  }

  /// Обработка данных о весе
  void _processWeightData(List<HealthDataPoint> rawPoints) {
    for (var point in rawPoints) {
      final key = DateKey(point.dateFrom);

      if (_weightCache.containsKey(key)) continue;

      final value = point.value;
      if (value is NumericHealthValue) {
        _weightCache[key] = WeightDay(date: key, weight: value.numericValue.toDouble());
      }
    }
  }

  // /// Обработка данных об энергобалансе (приход/расход)
  // void _processEnergyBalanceData(List<HealthDataPoint> nutritionPoints, DateTime now) {
  //   final Map<DateKey, _DailyNutritionDTO> dailyMap = {};

  //   // Инициализируем карту пустыми значениями для последних N дней
  //   for (int i = 0; i < selectedDurationInDays; i++) {
  //     final date = now.subtract(Duration(days: i));
  //     final key = DateKey(date);
  //     dailyMap[key] = _DailyNutritionDTO(date: date);
  //   }

  //   // Set для отслеживания уже обработанных записей (дедупликация)
  //   final processedRecordIds = <String>{};

  //   // Фильтруем только данные из FatSecret (или другого основного источника)
  //   const primarySource = 'com.fatsecret.android';
  //   final filteredNutritionPoints = nutritionPoints.where((e) => e.sourceName == primarySource).toList();

  //   // Обрабатываем данные о питании
  //   for (var point in filteredNutritionPoints) {
  //     final date = point.dateFrom;
  //     final key = DateKey(date);

  //     if (!dailyMap.containsKey(key)) continue;

  //     // Генерируем уникальный ключ для записи
  //     final recordId = _generateRecordUniqueId(point);

  //     // Пропускаем, если запись уже была обработана
  //     if (processedRecordIds.contains(recordId)) {
  //       if (kDebugMode) {
  //         debugPrint('Skipping duplicate nutrition record: $recordId');
  //       }
  //       continue;
  //     }
  //     processedRecordIds.add(recordId);

  //     final accumulator = dailyMap[key]!;
  //     _parseAndAddToAccumulator(point, accumulator);
  //   }

  //   final result = dailyMap.values.toList();
  //   result.sort((a, b) => a.date.compareTo(b.date));

  //   return result
  //       .map(
  //         (acc) => NutritionDay(
  //           date: acc.date,
  //           calories: acc.calories,
  //           protein: acc.protein,
  //           fat: acc.fat,
  //           carbs: acc.carbs,
  //         ),
  //       )
  //       .toList();
  // }

  /// Обработка данных об шагах (приход/расход)
  List<StepsDay> _processStepsData(List<HealthDataPoint> rawPoints) {
    final Map<DateKey, StepsDay> dailyMap = {};

    for (var point in rawPoints) {
      final date = point.dateFrom;
      final key = DateKey(date);

      final value = point.value;
      if (value is NumericHealthValue) {
        final steps = value.numericValue;
        dailyMap[key] =
            dailyMap[key]?.copyWithAddedSteps(steps: steps.toInt()) ??
            StepsDay(date: DateKey(date), steps: steps.toInt());
      }
    }

    final result = dailyMap.values.toList();
    result.sort((a, b) => a.date.compareTo(b.date));

    return result;
  }

  /// Вычисление EMA (Exponential Moving Average)
  List<WeightDay> _processEMA(List<WeightDay> data, int period) {
    final cachedDates = _emaCache.values.map((e) => e.date).toSet();
    final clearedData = data..removeWhere((e) => cachedDates.contains(e.date));
    final fullData = [..._emaCache.values, ...clearedData];

    fullData.sort((a, b) => a.date.value.isBefore(b.date.value) ? -1 : 1);

    final multiplier = 2 / (period + 1);

    final result = <WeightDay>[];

    // Первое значение EMA - это просто первое значение веса
    double ema = fullData.first.weight;
    result.add(WeightDay(date: fullData.first.date, weight: ema));

    // Вычисляем EMA для остальных точек
    for (int i = 1; i < fullData.length; i++) {
      ema = (fullData[i].weight - ema) * multiplier + ema;
      result.add(WeightDay(date: fullData[i].date, weight: ema));
    }

    _emaCache.clear();
    _emaCache = Map.fromEntries(result.map((e) => MapEntry(e.date, e)));

    return result;
  }

  /// Период EMA в зависимости от выбранного диапазона
  int get _emaPeriod {
    if (selectedDurationInDays >= 20) return 10;
    if (selectedDurationInDays >= 10) return 5;
    return 3;
  }

  /// Генерация уникального идентификатора для записи
  String _generateRecordUniqueId(HealthDataPoint point) {
    if (point.uuid.isNotEmpty) return point.uuid;

    final source = point.sourceName;
    final timestamp = point.dateFrom.millisecondsSinceEpoch;
    final type = point.type.toString();

    String valueHash = '0';
    final value = point.value;
    if (value is NumericHealthValue) {
      valueHash = value.numericValue.toString();
    } else if (value is NutritionHealthValue) {
      valueHash = '${value.calories}_${value.protein}_${value.fat}_${value.carbs}';
    }

    return '$source|$timestamp|$type|$valueHash';
  }

  void _parseAndAddToAccumulator(HealthDataPoint point, _DailyNutritionDTO acc) {
    final value = point.value;
    final type = point.type;

    if (value is NumericHealthValue) {
      double val = value.numericValue.toDouble();

      switch (type) {
        case HealthDataType.DIETARY_ENERGY_CONSUMED:
        case HealthDataType.NUTRITION:
          acc.calories += val;
          break;
        case HealthDataType.DIETARY_PROTEIN_CONSUMED:
          acc.protein += val;
          break;
        case HealthDataType.DIETARY_FATS_CONSUMED:
          acc.fat += val;
          break;
        case HealthDataType.DIETARY_CARBS_CONSUMED:
          acc.carbs += val;
          break;
        default:
          break;
      }
    } else if (value is NutritionHealthValue) {
      acc.calories += value.calories?.toDouble() ?? 0.0;
      acc.protein += value.protein?.toDouble() ?? 0.0;
      acc.fat += value.fat?.toDouble() ?? 0.0;
      acc.carbs += value.carbs?.toDouble() ?? 0.0;
    }
  }

  Future<void> setDate({DateTime? start, DateTime? end}) async {
    if (start != null) _start = start;
    if (end != null) _end = end;

    await loadData();

    _setChartsData();

    notifyListeners();
  }

  void _setChartsData() {
    _weightData = _weightCache.entries
        .where((k) => k.key.value.isInsideInterval(start, end))
        .map((e) => e.value)
        .sorted((a, b) => a.date.compareTo(b.date));

    _emaData = _emaCache.entries
        .where((k) => k.key.value.isInsideInterval(start, end))
        .map((e) => e.value)
        .sorted((a, b) => a.date.compareTo(b.date));

    _nutritionData = _nutritionCache.entries
        .where((k) => k.key.value.isInsideInterval(start, end))
        .map((e) => e.value)
        .sorted((a, b) => a.date.compareTo(b.date));

    _sleepData = _sleepCache.entries
        .where((k) => k.key.value.isInsideInterval(start, end))
        .map((e) => e.value)
        .sorted((a, b) => a.date.compareTo(b.date));

    _stepsData = _stepsCache.entries
        .where((k) => k.key.value.isInsideInterval(start, end))
        .map((e) => e.value)
        .sorted((a, b) => a.date.compareTo(b.date));


  }
}

/// Вспомогательный класс для накопления данных о питании за один день
class _DailyNutritionDTO {
  final DateTime date;
  double calories = 0;
  double protein = 0;
  double fat = 0;
  double carbs = 0;
  double basalMetabolism = 0;
  double activityCalories = 0;

  _DailyNutritionDTO({required this.date});
}
