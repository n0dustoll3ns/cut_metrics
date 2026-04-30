import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:health_widgets/domain/nutrition.dart';
import 'package:health_widgets/repo/health.dart';

class NutritionViewModel extends ChangeNotifier {
  static const String primarySource = 'com.fatsecret.android'; //TODO добавить выбор основного источника
  static const dataTypes = [HealthDataType.NUTRITION];
  final HealthRepository repository;

  List<NutritionDay> _nutritionData = [];
  int _selectedDays = 7;
  bool _isLoading = false;
  String? _error;

  // Геттеры
  List<NutritionDay> get nutritionData => _nutritionData;
  int get selectedDays => _selectedDays;
  bool get isLoading => _isLoading;
  String? get error => _error;

  NutritionViewModel(this.repository);

  /// Инициализация: запрос прав и загрузка данных
  Future<void> authorizeAndFetchNutritionData() async {
    try {
      bool granted = await repository.checkAndRequestPermissions(dataTypes);
      if (!granted) {
        _error = "Permission denied or SDK unavailable";
        notifyListeners();
        return;
      }
      await _fetchAndProcess();
    } catch (e) {
      _error = "Auth error: $e";
      notifyListeners();
    }
  }

  /// Смена количества отображаемых дней
  Future<void> setSelectedDays(int days) async {
    if (_selectedDays == days) return;
    _selectedDays = days;
    notifyListeners();
    await _fetchAndProcess();
  }

  /// Основная логика загрузки и обработки
  Future<void> _fetchAndProcess() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays + 1));

      final rawPoints = await repository.fetchRawData(types: dataTypes, startDate: startDate, endDate: now);

      _nutritionData = _processNutritionData(
        rawPoints: rawPoints.where((e) => e.sourceName == primarySource).toList(),
        daysToAnalyze: _selectedDays,
        now: now,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = "Failed to fetch nutrition data: $e";
      _isLoading = false;
      notifyListeners();
      debugPrint("Nutrition Error: $e");
    }
  }

  /// Логика агрегации данных с дедупликацией записей
  List<NutritionDay> _processNutritionData({
    required List<HealthDataPoint> rawPoints,
    required int daysToAnalyze,
    required DateTime now,
  }) {
    final Map<String, _DailyNutritionAccumulator> dailyMap = {};

    // Инициализируем карту пустыми значениями для последних N дней
    for (int i = 0; i < daysToAnalyze; i++) {
      final date = now.subtract(Duration(days: i));
      final key = _getDateKey(date);
      dailyMap[key] = _DailyNutritionAccumulator(date: date);
    }

    // 🔥 Set для отслеживания уже обработанных записей (дедупликация)
    final processedRecordIds = <String>{};

    for (var point in rawPoints) {
      final date = point.dateFrom;
      final key = _getDateKey(date);

      if (!dailyMap.containsKey(key)) continue;

      // 🔥 Генерируем уникальный ключ для записи
      final recordId = _generateRecordUniqueId(point);

      // 🔥 Пропускаем, если запись уже была обработана
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

  /// 🔥 Генерация уникального идентификатора для записи
  /// Приоритет: uuid > композитный ключ (источник + время + тип + значение)
  String _generateRecordUniqueId(HealthDataPoint point) {
    // Если есть UUID — используем его (самый надёжный вариант)
    if (point.uuid.isNotEmpty) point.uuid;

    // Фоллбэк: композитный ключ из доступных полей
    final source = point.sourceName;
    final timestamp = point.dateFrom.millisecondsSinceEpoch;
    final type = point.type.toString();

    // Значение: извлекаем числовое представление для ключа
    String valueHash = '0';
    final value = point.value;
    if (value is NumericHealthValue) {
      valueHash = value.numericValue.toString();
    } else if (value is NutritionHealthValue) {
      // Хешируем основные поля нутриента
      valueHash = '${value.calories}_${value.protein}_${value.fat}_${value.carbs}';
    }

    // Формируем ключ: источник|время|тип|значение
    return '$source|$timestamp|$type|$valueHash';
  }

  void _parseAndAddToAccumulator(HealthDataPoint point, _DailyNutritionAccumulator acc) {
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

/// Вспомогательный класс для накопления данных за один день
class _DailyNutritionAccumulator {
  final DateTime date;
  double calories = 0;
  double protein = 0;
  double fat = 0;
  double carbs = 0;

  _DailyNutritionAccumulator({required this.date});
}
