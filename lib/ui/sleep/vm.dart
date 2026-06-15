import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:cut_metrics/domain.dart';
import 'package:cut_metrics/domain/sleep.dart';
import 'package:cut_metrics/repo/health.dart';

class SleepViewModel extends ChangeNotifier {
  // Внедряем зависимости (в реальном проекте лучше через DI, например get_it)
  final HealthRepository _repository;
  final SleepAnalyzer _analyzer = SleepAnalyzer();

  List<SleepDay> _sleepData = [];
  int _selectedDays = 7;
  bool _isLoading = false;
  String? _error;

  List<SleepDay> get sleepData => _sleepData;
  int get selectedDays => _selectedDays;
  bool get isLoading => _isLoading;
  String? get error => _error;

  SleepViewModel(HealthRepository repository) : _repository = repository;

  Future<void> authorizeAndFetchSleepData() async {
    final types = [
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_REM,
    ];

    try {
      bool granted = await _repository.checkAndRequestPermissions(types);
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

  Future<void> setSelectedDays(int days) async {
    if (_selectedDays == days) return;
    _selectedDays = days;
    notifyListeners();
    await _fetchAndProcess();
  }

  Future<void> _fetchAndProcess() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final startDate = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: _selectedDays + 2)); // Запас для ночей

      // 1. Получаем сырые данные через Репозиторий
      final rawPoints = await _repository.fetchRawData(
        types: [
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.SLEEP_REM,
        ],
        startDate: startDate,
        endDate: now,
      );

      // 2. Обрабатываем данные через Сервис/Анализатор
      _sleepData = _analyzer.processSleepData(
        rawPoints: rawPoints,
        daysToAnalyze: _selectedDays,
        now: now,
      );

      _isLoading = false;
      notifyListeners();

      // Триггер обновления виджета можно оставить здесь или вынести в отдельный метод
      // Если путь к картинке уже известен из прошлого рендера, можно обновить виджет сразу
    } catch (e) {
      _error = "Failed to fetch data: $e";
      _isLoading = false;
      notifyListeners();
      debugPrint("Error: $e");
    }
  }
}
