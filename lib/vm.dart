import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:health_widgets/domain.dart';
import 'package:home_widget/home_widget.dart';

// Вспомогательный класс для работы с интервалами внутри алгоритма
// Добавил sourceName для отладки, чтобы видеть, кто кого переписывает
class _SleepInterval {
  DateTime start;
  DateTime end;
  HealthDataType type;
  String sourceName;

  _SleepInterval({required this.start, required this.end, required this.type, required this.sourceName});

  @override
  String toString() {
    return '${_fmtTime(start)}-${_fmtTime(end)} | ${type.toString().split('.').last.padRight(6)} | Src: $sourceName';
  }

  String _fmtTime(DateTime t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
}

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

    final types = [HealthDataType.SLEEP_DEEP, HealthDataType.SLEEP_LIGHT, HealthDataType.SLEEP_REM];
    final permissions = List.filled(types.length, HealthDataAccess.READ);

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
    notifyListeners();
    await _fetchSleepData();
  }

  /// Основная бизнес-логика получения и обработки данных
  Future<void> _fetchSleepData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      // Берем запас +2 дня, чтобы гарантированно захватить ночи
      final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays + 2));

      debugPrint(">>> START FETCHING SLEEP DATA");

      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.SLEEP_DEEP, HealthDataType.SLEEP_LIGHT, HealthDataType.SLEEP_REM],
        startTime: startDate,
        endTime: now,
      );

      debugPrint("Raw points count: ${healthData.length}");

      // 1. Преобразуем HealthDataPoint в простые интервалы
      List<_SleepInterval> intervals = [];
      for (var point in healthData) {
        if (point.value is NumericHealthValue) {
          if ((point.value as NumericHealthValue).numericValue > 0) {
            intervals.add(
              _SleepInterval(
                start: point.dateFrom,
                end: point.dateTo,
                type: point.type,
                sourceName: point.sourceName,
              ),
            );
          }
        }
      }

      // 2. Сортируем интервалы по времени начала
      intervals.sort((a, b) => a.start.compareTo(b.start));

      debugPrint("--- SORTED INTERVALS (Before Merge) ---");
      for (var i in intervals) {
        debugPrint("  IN: $i");
      }

      // 3. ОБРАБОТКА ПЕРЕСЕЧЕНИЙ С ПРИОРИТЕТОМ ПОСЛЕДНЕГО (OVERWRITE)
      List<_SleepInterval> processedIntervals = [];

      for (var current in intervals) {
        if (processedIntervals.isEmpty) {
          processedIntervals.add(current);
        } else {
          var last = processedIntervals.last;

          // Проверяем пересечение: текущий начинается раньше, чем заканчивается предыдущий
          if (current.start.isBefore(last.end)) {
            debugPrint("⚠️ OVERLAP DETECTED!");
            debugPrint("   Existing: $last");
            debugPrint("   Incoming: $current");

            // Логика "Вытеснения":
            // Мы считаем верными данные текущего (incoming) интервала.
            // Поэтому мы должны обрезать предыдущий (last) интервал так,
            // чтобы он заканчивался там, где начинается текущий.

            if (current.start.isAfter(last.start)) {
              debugPrint("   -> TRIMMING Existing end from ${last.end} to ${current.start}");
              last.end = current.start;

              // Если после обрезки предыдущий интервал стал слишком коротким или нулевым,
              // его можно было бы удалить, но оставим для целостности истории,
              // если длительность > 0.
              if (last.end.difference(last.start).inMinutes <= 0) {
                debugPrint("   -> Existing interval became empty after trim. Removing it.");
                processedIntervals.removeLast();
              }
            } else {
              // Текущий интервал начался раньше или одновременно с последним.
              // Это значит, что текущий интервал полностью или частично перекрывает начало последнего.
              // Поскольку текущий имеет приоритет (как более "свежий" в логике сортировки/источника),
              // мы можем заменить последний текущим, если текущий длиннее или покрывает его.
              // Но проще всего в данном алгоритме просто добавить текущий,
              // а последний удалить, если он полностью внутри текущего, или обрезать последний с начала?
              // Упрощение: если current.start <= last.start, то current "победил" в начале.
              // Удаляем last, и даем текущему шанс слиться с пред-предыдущим на следующей итерации?
              // Нет, мы идем линейно.
              // Просто заменяем last на current, если current.start <= last.start.
              debugPrint("   -> Incoming starts before Existing. Replacing Existing with Incoming.");
              processedIntervals.removeLast();
              // Важно: нам нужно проверить слияние/пересечение с новым "последним" элементом списка.
              // Поэтому мы не добавляем current сразу, а пытаемся сравнить его снова.
              // Для простоты реализации в цикле: добавим current, но на следующей итерации
              // он может быть обрезан следующим элементом.
              // Однако, чтобы корректно обработать случай "вложенности",
              // лучше просто добавить current. Он "съест" хвост предыдущего.
            }

            // Добавляем текущий интервал.
            // Он теперь не пересекается с предыдущим (так как мы обрезали предыдущий до current.start)
            processedIntervals.add(current);
            debugPrint("   -> Result: Added Incoming. Previous was trimmed/replaced.");
          } else {
            // Нет пересечения
            processedIntervals.add(current);
          }
        }
      }

      debugPrint("--- PROCESSED INTERVALS (After Overwrite Logic) ---");
      double totalMinutes = 0;
      for (var i in processedIntervals) {
        int mins = i.end.difference(i.start).inMinutes;
        totalMinutes += mins;
        debugPrint("  FINAL: $i (${mins} min)");
      }
      debugPrint("Total processed minutes: ${totalMinutes.toInt()}");

      // 4. Распределение по дням
      Map<String, Map<HealthDataType, double>> dailyStats = {};

      // Инициализируем карту нулями для нужного диапазона
      for (int i = 0; i < _selectedDays; i++) {
        DateTime date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        String key = _getDateKey(date);
        dailyStats[key] = {
          HealthDataType.SLEEP_DEEP: 0.0,
          HealthDataType.SLEEP_LIGHT: 0.0,
          HealthDataType.SLEEP_REM: 0.0,
        };
      }

      for (var interval in processedIntervals) {
        // Логика определения дня:
        // Если сон начался после 12:00, считаем его относящимся к следующему дню (дню пробуждения).
        DateTime targetDate = interval.start;
        if (interval.start.hour >= 12) {
          targetDate = interval.start.add(Duration(days: 1));
        }

        String key = _getDateKey(targetDate);

        if (dailyStats.containsKey(key)) {
          double durationHours = interval.end.difference(interval.start).inMinutes / 60.0;

          // debugPrint("ASSIGNING: ${interval.type} ($durationHours h) to Day: $key");

          switch (interval.type) {
            case HealthDataType.SLEEP_DEEP:
              dailyStats[key]![HealthDataType.SLEEP_DEEP] =
                  (dailyStats[key]![HealthDataType.SLEEP_DEEP] ?? 0) + durationHours;
              break;
            case HealthDataType.SLEEP_LIGHT:
              dailyStats[key]![HealthDataType.SLEEP_LIGHT] =
                  (dailyStats[key]![HealthDataType.SLEEP_LIGHT] ?? 0) + durationHours;
              break;
            case HealthDataType.SLEEP_REM:
              dailyStats[key]![HealthDataType.SLEEP_REM] =
                  (dailyStats[key]![HealthDataType.SLEEP_REM] ?? 0) + durationHours;
              break;
            default:
              break;
          }
        }
      }

      // 5. Формируем итоговый список
      List<SleepDay> processedData = [];
      for (int i = 0; i < _selectedDays; i++) {
        DateTime date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        String key = _getDateKey(date);

        var stats =
            dailyStats[key] ??
            {HealthDataType.SLEEP_DEEP: 0.0, HealthDataType.SLEEP_LIGHT: 0.0, HealthDataType.SLEEP_REM: 0.0};

        processedData.add(
          SleepDay(
            date: date,
            deep: stats[HealthDataType.SLEEP_DEEP] ?? 0.0,
            light: stats[HealthDataType.SLEEP_LIGHT] ?? 0.0,
            rem: stats[HealthDataType.SLEEP_REM] ?? 0.0,
          ),
        );
      }

      processedData.sort((a, b) => a.date.compareTo(b.date));

      debugPrint("--- FINAL RESULTS ---");
      for (var day in processedData) {
        debugPrint(day.toString());
      }

      _sleepData = processedData;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = "Failed to fetch data: $e";
      _isLoading = false;
      notifyListeners();
      debugPrint("Error fetching sleep data: $e");
    }
  }

  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month}-${date.day}";
  }

  /// Логика сохранения изображения и обновления Home Widget
  Future<void> updateSystemWidget(String imagePath) async {
    try {
      await HomeWidget.saveWidgetData<String>('chart_path', imagePath);
      await HomeWidget.updateWidget(name: 'SleepWidgetProvider', androidName: 'SleepWidgetProvider');
    } catch (e) {
      debugPrint("Widget update failed: $e");
    }
  }
}
