import 'dart:async';
import 'package:flutter/foundation.dart';
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
    loadData();
  }

  // Данные для графиков
  List<WeightDay> _weightData = [];
  List<WeightDay> _emaData = [];
  List<NutritionDay> _nutritionData = [];
  List<SleepDay> _sleepData = [];
  List<StepsDay> _stepsData = [];

  // Состояние
  DateTime _start = DateTime.now().subtract(Duration(days: 7));
  DateTime _end = DateTime.now();
  bool _isLoading = false;
  String? _error;

  void setDate({DateTime? start, DateTime? end}) {
    if (start != null) _start = start;
    if (end != null) _end = end;
    notifyListeners();
  }

  /// Инициализация: запрос прав и загрузка всех данных
  Future<void> loadData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Запрашиваем права на все типы данных сразу

      bool granted = await repo.checkAndRequestPermissions(allDataTypes);
      if (!granted) {
        _error = "Permission denied or SDK unavailable";
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Загружаем все данные параллельно

      final (weightPoints, nutritionPoints, sleepPoints) = (
        await repo.fetchRawData(types: weightDataTypes, startDate: _start, endDate: _end),
        await repo.fetchRawData(types: nutritionDataTypes, startDate: _start, endDate: _end),
        await repo.fetchRawData(types: sleepDataTypes, startDate: _start, endDate: _end),
      );

      // Получаем агрегированные данные о шагах (устраняет дубликаты от разных источников)
      final aggregatedSteps = await repo.fetchAggregatedSteps(startDate: _start, endDate: _end);

      // Обрабатываем вес с EMA
      _weightData = _processWeightData(weightPoints);
      _emaData = _calculateEMA(_weightData, _getEmaPeriod());

      // Обрабатываем энергобаланс
      _nutritionData = _processEnergyBalanceData(nutritionPoints, _end);

      // Обрабатываем сон через SleepAnalyzer
      _sleepData = _sleepAnalyzer.processSleepData(
        rawPoints: sleepPoints,
        daysToAnalyze: selectedDurationInDays,
        now: _end,
      );

      // Обрабатываем шаги
      _stepsData = _processStepsData(aggregatedSteps);

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
  List<WeightDay> _processWeightData(List<HealthDataPoint> rawPoints) {
    final Map<String, _WeightDTO> dailyMap = {};

    // Инициализируем карту пустыми значениями для последних N дней
    for (int i = 0; i < selectedDurationInDays; i++) {
      final date = _end.subtract(Duration(days: i));
      final key = _getDateKey(date);
      dailyMap[key] = _WeightDTO(date: date);
    }

    for (var point in rawPoints) {
      final date = point.dateFrom;
      final key = _getDateKey(date);

      if (!dailyMap.containsKey(key)) continue;

      final value = point.value;
      if (value is NumericHealthValue) {
        final accumulator = dailyMap[key]!;
        accumulator.addWeight(value.numericValue.toDouble());
      }
    }

    final result = dailyMap.values.where((e) => e.weight != null).toList();
    result.sort((a, b) => a.date.compareTo(b.date));

    return result
        .where((e) => e.weight != null)
        .map((acc) => WeightDay(date: acc.date, weight: acc.weight!))
        .toList();
  }

  /// Обработка данных об энергобалансе (приход/расход)
  List<NutritionDay> _processEnergyBalanceData(List<HealthDataPoint> nutritionPoints, DateTime now) {
    final Map<String, _DailyNutritionDTO> dailyMap = {};

    // Инициализируем карту пустыми значениями для последних N дней
    for (int i = 0; i < selectedDurationInDays; i++) {
      final date = now.subtract(Duration(days: i));
      final key = _getDateKey(date);
      dailyMap[key] = _DailyNutritionDTO(date: date);
    }

    // Set для отслеживания уже обработанных записей (дедупликация)
    final processedRecordIds = <String>{};

    // Фильтруем только данные из FatSecret (или другого основного источника)
    const primarySource = 'com.fatsecret.android';
    final filteredNutritionPoints = nutritionPoints.where((e) => e.sourceName == primarySource).toList();

    // Обрабатываем данные о питании
    for (var point in filteredNutritionPoints) {
      final date = point.dateFrom;
      final key = _getDateKey(date);

      if (!dailyMap.containsKey(key)) continue;

      // Генерируем уникальный ключ для записи
      final recordId = _generateRecordUniqueId(point);

      // Пропускаем, если запись уже была обработана
      if (processedRecordIds.contains(recordId)) {
        if (kDebugMode) {
          debugPrint('Skipping duplicate nutrition record: $recordId');
        }
        continue;
      }
      processedRecordIds.add(recordId);

      final accumulator = dailyMap[key]!;
      _parseAndAddToAccumulator(point, accumulator);
    }

    final result = dailyMap.values.toList();
    result.sort((a, b) => a.date.compareTo(b.date));

    return result
        .map(
          (acc) => NutritionDay(
            date: acc.date,
            calories: acc.calories,
            protein: acc.protein,
            fat: acc.fat,
            carbs: acc.carbs,
          ),
        )
        .toList();
  }

  /// Обработка агрегированных данных о шагах (устранение дубликатов)
  /// Принимает Map<String, int> где ключ - дата в формате "YYYY-MM-DD", значение - количество шагов
  List<StepsDay> _processStepsData(Map<String, int> aggregatedSteps) {
    final List<StepsDay> result = [];

    // Преобразуем агрегированные данные в список StepsDay
    for (var entry in aggregatedSteps.entries) {
      try {
        // Парсим дату из ключа формата "YYYY-MM-DD"
        final dateParts = entry.key.split('-');
        if (dateParts.length != 3) {
          debugPrint('⚠️ Invalid date format: ${entry.key}');
          continue;
        }

        final year = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final day = int.parse(dateParts[2]);
        final date = DateTime(year, month, day);

        // Добавляем null-safety проверку: если шагов нет или значение некорректно, пропускаем
        final steps = entry.value;
        if (steps < 0) {
          debugPrint('⚠️ Negative steps value for ${entry.key}: $steps');
          continue;
        }

        result.add(StepsDay(date: date, steps: steps));
      } catch (e) {
        debugPrint('❌ Error parsing steps data for ${entry.key}: $e');
      }
    }

    // Сортируем по дате
    result.sort((a, b) => a.date.compareTo(b.date));

    return result;
  }

  /// Вычисление EMA (Exponential Moving Average)
  List<WeightDay> _calculateEMA(List<WeightDay> data, int period) {
    if (data.isEmpty) return [];

    final result = <WeightDay>[];
    final multiplier = 2 / (period + 1);

    // Первое значение EMA - это просто первое значение веса
    double ema = data.first.weight;
    result.add(WeightDay(date: data.first.date, weight: ema));

    // Вычисляем EMA для остальных точек
    for (int i = 1; i < data.length; i++) {
      ema = (data[i].weight - ema) * multiplier + ema;
      result.add(WeightDay(date: data[i].date, weight: ema));
    }

    return result;
  }

  /// Период EMA в зависимости от выбранного диапазона
  int _getEmaPeriod() {
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

  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}

/// Вспомогательный класс для накопления данных о весе за один день
class _WeightDTO {
  final DateTime date;
  double? weight;

  _WeightDTO({required this.date});

  void addWeight(double w) {
    weight = w;
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
