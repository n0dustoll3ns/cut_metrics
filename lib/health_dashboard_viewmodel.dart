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
class HealthDashboardViewModel extends ChangeNotifier {
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

  // Данные для графиков
  List<WeightDay> _weightData = [];
  List<WeightDay> _emaData = [];
  List<NutritionDay> _nutritionData = [];
  List<SleepDay> _sleepData = [];

  // Состояние
  int _selectedDays = 14;
  bool _isLoading = false;
  String? _error;

  // Геттеры
  List<WeightDay> get weightData => _weightData;
  List<WeightDay> get emaData => _emaData;
  List<NutritionDay> get nutritionData => _nutritionData;
  List<SleepDay> get sleepData => _sleepData;
  int get selectedDays => _selectedDays;
  bool get isLoading => _isLoading;
  String? get error => _error;

  HealthDashboardViewModel({required HealthRepository repository, SleepAnalyzer? sleepAnalyzer})
    : repo = repository,
      _sleepAnalyzer = sleepAnalyzer ?? SleepAnalyzer() {
    loadData();
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

      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays + 2));

      // Загружаем все данные параллельно

      final (weightPoints, nutritionPoints, activityPoints, sleepPoints) = (
        await repo.fetchRawData(types: weightDataTypes, startDate: startDate, endDate: now),
        await repo.fetchRawData(types: nutritionDataTypes, startDate: startDate, endDate: now),
        await repo.fetchRawData(types: stepsDataTypes, startDate: startDate, endDate: now),
        await repo.fetchRawData(types: sleepDataTypes, startDate: startDate, endDate: now),
      );

      // Обрабатываем вес с EMA
      _weightData = _processWeightData(weightPoints, now);
      _emaData = _calculateEMA(_weightData, _getEmaPeriod());

      // Обрабатываем энергобаланс
      _nutritionData = _processEnergyBalanceData(nutritionPoints, activityPoints, now);

      // Обрабатываем сон через SleepAnalyzer
      _sleepData = _sleepAnalyzer.processSleepData(
        rawPoints: sleepPoints,
        daysToAnalyze: _selectedDays,
        now: now,
      );

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
  List<WeightDay> _processWeightData(List<HealthDataPoint> rawPoints, DateTime now) {
    final Map<String, _WeightDTO> dailyMap = {};

    // Инициализируем карту пустыми значениями для последних N дней
    for (int i = 0; i < _selectedDays; i++) {
      final date = now.subtract(Duration(days: i));
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
  List<NutritionDay> _processEnergyBalanceData(
    List<HealthDataPoint> nutritionPoints,
    List<HealthDataPoint> activityPoints,
    DateTime now,
  ) {
    final Map<String, _DailyNutritionDTO> dailyMap = {};

    // Инициализируем карту пустыми значениями для последних N дней
    for (int i = 0; i < _selectedDays; i++) {
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

    // Обрабатываем данные об активности (расход калорий)
    for (var point in activityPoints) {
      final date = point.dateFrom;
      final key = _getDateKey(date);

      if (!dailyMap.containsKey(key)) continue;

      final value = point.value;
      if (value is NumericHealthValue) {
        final accumulator = dailyMap[key]!;
        final kcal = value.numericValue.toDouble();

        switch (point.type) {
          case HealthDataType.BASAL_ENERGY_BURNED:
            accumulator.basalMetabolism += kcal;
            break;
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            accumulator.activityCalories += kcal;
            break;
          default:
            break;
        }
      }
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
            basalMetabolism: acc.basalMetabolism,
            activityCalories: acc.activityCalories,
          ),
        )
        .toList();
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
    if (_selectedDays >= 30) return 10;
    if (_selectedDays >= 14) return 5;
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

  /// Смена количества отображаемых дней
  Future<void> setSelectedDays(int days) async {
    if (_selectedDays == days) return;
    _selectedDays = days;
    notifyListeners();
    await loadData();
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
