import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:cut_metrics/domain/weight.dart';
import 'package:cut_metrics/repo/health.dart';

class WeightViewModel extends ChangeNotifier {
  final HealthRepository repository;

  List<WeightDay> _weightData = [];
  List<WeightDay> _emaData = []; // Данные для линии тренда EMA
  int _selectedDays = 7;
  bool _isLoading = false;
  String? _error;
  double? _averageWeight;
  double? _weightDynamicsPercent; // Динамика веса в процентах за 7 дней

  // Геттеры
  List<WeightDay> get weightData => _weightData;
  List<WeightDay> get emaData => _emaData;
  int get selectedDays => _selectedDays;
  bool get isLoading => _isLoading;
  String? get error => _error;
  double? get averageWeight => _averageWeight;
  double? get weightDynamicsPercent => _weightDynamicsPercent;

  WeightViewModel(this.repository) {
    _init();
  }

  void _init() => _authorizeAndFetchWeightData();

  /// Инициализация: запрос прав и загрузка данных
  Future<void> _authorizeAndFetchWeightData() async {
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

  /// Вычисление EMA (Exponential Moving Average) для линии тренда
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

  /// Вычисление динамики веса в процентах за указанное количество дней
  double? _calculateWeightDynamics(List<WeightDay> data, int days) {
    if (data.length < 2) return null;

    // Берём последнее измерение
    final currentWeight = data.last.weight;

    // Ищем измерение, которое было примерно `days` дней назад
    final targetDate = data.last.date.subtract(Duration(days: days));

    // Находим ближайшее измерение к целевой дате
    WeightDay? pastDay;
    for (var day in data.reversed) {
      if (day.date.isBefore(targetDate) || day.date.isAtSameMomentAs(targetDate)) {
        pastDay = day;
        break;
      }
    }

    // Если не нашли прошлое измерение, берём первое доступное
    if (pastDay == null) {
      if (data.length < 2) return null;
      pastDay = data.first;
    }

    // Считаем процентное изменение: ((текущий - прошлый) / прошлый) * 100
    final pastWeight = pastDay.weight;
    if (pastWeight == 0) return null;

    return ((currentWeight - pastWeight) / pastWeight) * 100;
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

      _weightData = _processWeightData(rawPoints: rawPoints, daysToAnalyze: _selectedDays, now: now);

      // Вычисляем EMA для линии тренда
      // Период EMA зависит от количества дней: для 14 дней - период 5, для 30 дней - период 10, иначе - период 3
      int emaPeriod;
      if (_selectedDays >= 30) {
        emaPeriod = 10;
      } else if (_selectedDays >= 14) {
        emaPeriod = 5;
      } else {
        emaPeriod = 3;
      }
      _emaData = _calculateEMA(_weightData, emaPeriod);

      // Вычисляем средний вес
      if (_weightData.isNotEmpty) {
        _averageWeight = _weightData.map((e) => e.weight).reduce((a, b) => a + b) / _weightData.length;
      } else {
        _averageWeight = null;
      }

      // Вычисляем динамику веса в процентах за 7 дней
      _weightDynamicsPercent = _calculateWeightDynamics(_weightData, 7);

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
