import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:health_widgets/domain.dart';
import 'package:home_widget/home_widget.dart';

class SleepViewModel extends ChangeNotifier {
  SleepViewModel() {
    _init();
  }

  final Health _health = Health();

  List<SleepDay> _sleepData = [];
  int _selectedDays = 7;
  bool _isLoading = false;
  String? _error;

  // Геттеры
  List<SleepDay> get sleepData => _sleepData;
  int get selectedDays => _selectedDays;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Инициализация и настройка Health
  Future<void> _init() async {
    await _health.configure();
  }

  /// Авторизация и запуск загрузки данных
  Future<void> authorizeAndFetch() async {
    var status = await _health.getHealthConnectSdkStatus();
    if (status != HealthConnectSdkStatus.sdkAvailable) {
      _error = "Health Connect SDK not available";
      notifyListeners();
      return;
    }

    final types = [HealthDataType.SLEEP_SESSION];
    final permissions = [HealthDataAccess.READ];

    try {
      bool? hasPermissions = await _health.hasPermissions(types, permissions: permissions);
      if (hasPermissions == false) {
        bool requested = await _health.requestAuthorization(types, permissions: permissions);
        if (!requested) {
          _error = "Permission denied";
          notifyListeners();
          return;
        }
      }
      await _fetchSleepData();
    } catch (e) {
      _error = "Authorization error: $e";
      notifyListeners();
    }
  }

  /// Изменение количества дней и перезагрузка
  Future<void> setSelectedDays(int days) async {
    if (_selectedDays == days) return;
    _selectedDays = days;
    notifyListeners(); // Сразу обновляем UI (показываем лоадер или пустой список)
    await _fetchSleepData();
  }

  /// Основная бизнес-логика получения и обработки данных
  Future<void> _fetchSleepData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      // Начало диапазона: сегодня минус (выбрано дней - 1)
      // Важно: берем начало дня
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays - 1));

      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_SESSION],
        startTime: startDate,
        endTime: now,
      );

      // ГРУППИРОВКА
      Map<DateTime, List<HealthDataPoint>> grouped = groupBy(healthData, (point) {
        return DateTime(point.dateFrom.year, point.dateFrom.month, point.dateFrom.day);
      });

      List<SleepDay> processedData = [];

      for (int i = 0; i < _selectedDays; i++) {
        DateTime date = startDate.add(Duration(days: i));
        DateTime key = DateTime(date.year, date.month, date.day);

        double dayDeep = 0, dayLight = 0, dayRem = 0;

        if (grouped.containsKey(key)) {
          for (var point in grouped[key]!) {
            // Безопасное приведение типов
            if (point.value is NumericHealthValue) {
              double totalMinutes = (point.value as NumericHealthValue).numericValue.toDouble();
              double totalHours = totalMinutes / 60;

              // Логика распределения фаз (как в исходном коде)
              dayDeep += totalHours * 0.25;
              dayLight += totalHours * 0.55;
              dayRem += totalHours * 0.20;
            }
          }
        }
        processedData.add(SleepDay(date: key, deep: dayDeep, light: dayLight, rem: dayRem));
      }

      _sleepData = processedData;
      _isLoading = false;
      notifyListeners();

      // Если данные есть, инициируем обновление домашнего виджета
      // Примечание: Сам скриншот делается в UI слое, но мы можем вызвать триггер
      if (_sleepData.isNotEmpty) {
        // Мы не можем сделать скриншот здесь, так как нет доступа к RenderBox.
        // View должен подписаться на изменения или вызвать метод обновления виджета после отрисовки.
      }
    } catch (e) {
      _error = "Failed to fetch data: $e";
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Логика сохранения изображения и обновления Home Widget
  /// Принимает путь к файлу изображения, созданному в UI слое
  Future<void> updateSystemWidget(String imagePath) async {
    try {
      await HomeWidget.saveWidgetData<String>('chart_path', imagePath);
      await HomeWidget.updateWidget(name: 'SleepWidgetProvider', androidName: 'SleepWidgetProvider');
    } catch (e) {
      debugPrint("Widget update failed: $e");
    }
  }
}
