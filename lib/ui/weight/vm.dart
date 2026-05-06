import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:health_widgets/domain/weight.dart';
import 'package:health_widgets/repo/health.dart';
import 'package:home_widget/home_widget.dart';

class WeightViewModel extends ChangeNotifier {
  final HealthRepository repository;

  List<WeightDay> _weightData = [];
  int _selectedDays = 7;
  bool _isLoading = false;
  String? _error;
  double? _averageWeight;

  // Геттеры
  List<WeightDay> get weightData => _weightData;
  int get selectedDays => _selectedDays;
  bool get isLoading => _isLoading;
  String? get error => _error;
  double? get averageWeight => _averageWeight;

  WeightViewModel(this.repository);

  /// Инициализация: запрос прав и загрузка данных
  Future<void> authorizeAndFetchWeightData() async {
    try {
      bool granted = await repository.checkAndRequestPermissions([HealthDataType.WEIGHT]);
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

      final rawPoints = await repository.fetchRawData(
        types: [HealthDataType.WEIGHT],
        startDate: startDate,
        endDate: now,
      );

      _weightData = _processWeightData(
        rawPoints: rawPoints,
        daysToAnalyze: _selectedDays,
        now: now,
      );

      // Вычисляем средний вес
      if (_weightData.isNotEmpty) {
        _averageWeight = _weightData.map((e) => e.weight).reduce((a, b) => a + b) / _weightData.length;
      } else {
        _averageWeight = null;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = "Failed to fetch weight data: $e";
      _isLoading = false;
      notifyListeners();
      debugPrint("Weight Error: $e");
    }
  }

  /// Логика агрегации данных по дням
  List<WeightDay> _processWeightData({
    required List<HealthDataPoint> rawPoints,
    required int daysToAnalyze,
    required DateTime now,
  }) {
    final Map<String, _WeightDTO> dailyMap = {};

    // Инициализируем карту пустыми значениями для последних N дней
    for (int i = 0; i < daysToAnalyze; i++) {
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

  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> updateSystemWidget(String path) async {
    try {
      await HomeWidget.saveWidgetData<String>('weight_chart_path', path);
      await HomeWidget.updateWidget(
        name: 'WeightWidgetProvider',
        androidName: 'WeightWidgetProvider',
      );
    } catch (e) {
      debugPrint("Widget update failed: $e");
    }
  }
}

/// Вспомогательный класс для накопления данных за один день
class _WeightDTO {
  final DateTime date;
  double? weight;

  _WeightDTO({required this.date});

  void addWeight(double w) {
    // Если это первое значение или оно больше предыдущего (берем последнее измерение за день)
    // Или можно брать среднее. Здесь берем последнее по времени измерения
    weight = w;
  }
}
