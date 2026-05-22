import 'package:health/health.dart';
import '../domain.dart';

class _SleepInterval {
  DateTime start;
  DateTime end;
  HealthDataType type;

  _SleepInterval({required this.start, required this.end, required this.type});
}

class SleepAnalyzer {
  List<SleepDay> processSleepData({
    required List<HealthDataPoint> rawPoints,
    required int daysToAnalyze,
    required DateTime now,
  }) {
    // 1. Фильтрация и конвертация в интервалы
    List<_SleepInterval> intervals = rawPoints
        .where(
          (point) =>
              point.value is NumericHealthValue && (point.value as NumericHealthValue).numericValue > 0,
        )
        .map((point) => _SleepInterval(start: point.dateFrom, end: point.dateTo, type: point.type))
        .toList();

    // 2. Сортировка
    intervals.sort((a, b) => a.start.compareTo(b.start));

    // 3. Слияние и разрешение конфликтов (Overwrite logic)
    List<_SleepInterval> processed = _mergeIntervals(intervals);

    // 4. Агрегация по дням
    return _aggregateByDay(processed, daysToAnalyze, now);
  }

  List<_SleepInterval> _mergeIntervals(List<_SleepInterval> intervals) {
    List<_SleepInterval> result = [];

    for (var current in intervals) {
      if (result.isEmpty) {
        result.add(current);
        continue;
      }

      var last = result.last;

      // Если есть пересечение
      if (current.start.isBefore(last.end)) {
        // Логика "последний побеждает": обрезаем предыдущий
        if (current.start.isAfter(last.start)) {
          last.end = current.start;
          if (last.end.difference(last.start).inMinutes <= 0) {
            result.removeLast();
          }
        } else {
          result.removeLast();
        }
        result.add(current);
      } else {
        result.add(current);
      }
    }
    return result;
  }

  List<SleepDay> _aggregateByDay(List<_SleepInterval> intervals, int days, DateTime now) {
    Map<String, Map<HealthDataType, double>> dailyStats = {};

    // Инициализация дней
    for (int i = 0; i < days; i++) {
      DateTime date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      String key = _dateKey(date);
      dailyStats[key] = {
        HealthDataType.SLEEP_DEEP: 0.0,
        HealthDataType.SLEEP_LIGHT: 0.0,
        HealthDataType.SLEEP_REM: 0.0,
      };
    }

    for (var interval in intervals) {
      // Определение "дня сна": если начался после 12:00, то это ночь следующего дня
      DateTime targetDate = interval.start;
      if (interval.start.hour >= 12) {
        targetDate = interval.start.add(const Duration(days: 1));
      }

      String key = _dateKey(targetDate);
      if (dailyStats.containsKey(key)) {
        double hours = interval.end.difference(interval.start).inMinutes / 60.0;

        switch (interval.type) {
          case HealthDataType.SLEEP_DEEP:
            dailyStats[key]![HealthDataType.SLEEP_DEEP] =
                (dailyStats[key]![HealthDataType.SLEEP_DEEP] ?? 0) + hours;
            break;
          case HealthDataType.SLEEP_LIGHT:
            dailyStats[key]![HealthDataType.SLEEP_LIGHT] =
                (dailyStats[key]![HealthDataType.SLEEP_LIGHT] ?? 0) + hours;
            break;
          case HealthDataType.SLEEP_REM:
            dailyStats[key]![HealthDataType.SLEEP_REM] =
                (dailyStats[key]![HealthDataType.SLEEP_REM] ?? 0) + hours;
            break;
          default:
            break;
        }
      }
    }

    // Сборка результата
    List<SleepDay> result = [];
    for (int i = 0; i < days; i++) {
      DateTime date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      String key = _dateKey(date);
      var stats = dailyStats[key]!;

      result.add(
        SleepDay(
          date: date,
          deep: stats[HealthDataType.SLEEP_DEEP] ?? 0.0,
          light: stats[HealthDataType.SLEEP_LIGHT] ?? 0.0,
          rem: stats[HealthDataType.SLEEP_REM] ?? 0.0,
        ),
      );
    }

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  String _dateKey(DateTime d) => "${d.year}-${d.month}-${d.day}";
}
