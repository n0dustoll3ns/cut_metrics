import 'package:cut_metrics/domain/date_extension.dart';
import 'package:health/health.dart';
import '../domain.dart';

// РЕФАКТОРИНГ: поля сделаны final, мутация заменена copyWith-паттерном
class _SleepInterval {
  final DateTime start;
  final DateTime end;
  final HealthDataType type;

  const _SleepInterval({required this.start, required this.end, required this.type});

  _SleepInterval withEnd(DateTime newEnd) =>
      _SleepInterval(start: start, end: newEnd, type: type);
}

class SleepAnalyzer {
  // Типы сна, которые мы отслеживаем
  static const _trackedTypes = {
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
  };

  List<SleepDay> processSleepData({
    required List<HealthDataPoint> rawPoints,
    required int daysToAnalyze,
    required DateTime now,
  }) {
    // 1. Фильтрация и конвертация в интервалы
    final intervals = rawPoints
        .where(
          (point) =>
              point.value is NumericHealthValue &&
              (point.value as NumericHealthValue).numericValue > 0,
        )
        .map((point) => _SleepInterval(start: point.dateFrom, end: point.dateTo, type: point.type))
        .toList();

    // 2. Сортировка
    intervals.sort((a, b) => a.start.compareTo(b.start));

    // 3. Слияние и разрешение конфликтов (Overwrite logic)
    final processed = _mergeIntervals(intervals);

    // 4. Агрегация по дням
    return _aggregateByDay(processed, daysToAnalyze, now);
  }

  List<_SleepInterval> _mergeIntervals(List<_SleepInterval> intervals) {
    final result = <_SleepInterval>[];

    for (final current in intervals) {
      if (result.isEmpty) {
        result.add(current);
        continue;
      }

      final last = result.last;

      // Если есть пересечение
      if (current.start.isBefore(last.end)) {
        // Логика "последний побеждает": обрезаем предыдущий
        if (current.start.isAfter(last.start)) {
          // РЕФАКТОРИНГ: вместо мутации last.end — заменяем объект через withEnd()
          final trimmed = last.withEnd(current.start);
          result.removeLast();
          if (trimmed.end.difference(trimmed.start).inMinutes > 0) {
            result.add(trimmed);
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
    // РЕФАКТОРИНГ: объединены два цикла по датам в один.
    // Инициализация и сборка результата происходят за один проход.
    final today = DateTime(now.year, now.month, now.day);

    // Инициализируем dailyStats сразу для всех дней
    final dailyStats = <DateKey, Map<HealthDataType, double>>{
      for (int i = 0; i < days; i++)
        DateKey(today.subtract(Duration(days: i))): {
          HealthDataType.SLEEP_DEEP: 0.0,
          HealthDataType.SLEEP_LIGHT: 0.0,
          HealthDataType.SLEEP_REM: 0.0,
        },
    };

    for (final interval in intervals) {
      // Определение "дня сна": если начался после 12:00, то это ночь следующего дня
      DateTime targetDate = interval.start;
      if (interval.start.hour >= 12) {
        targetDate = interval.start.add(const Duration(days: 1));
      }

      final key = DateKey(targetDate);
      if (!dailyStats.containsKey(key)) continue;

      // РЕФАКТОРИНГ: убраны избыточный switch и ?? 0 (карта уже инициализирована).
      // Обновляем только отслеживаемые типы.
      if (_trackedTypes.contains(interval.type)) {
        final hours = interval.end.difference(interval.start).inMinutes / 60.0;
        dailyStats[key]![interval.type] = dailyStats[key]![interval.type]! + hours;
      }
    }

    // Сборка результата из уже готовой карты
    final result = dailyStats.entries.map((entry) {
      final stats = entry.value;
      return SleepDay(
        date: entry.key,
        deep: stats[HealthDataType.SLEEP_DEEP]!,
        light: stats[HealthDataType.SLEEP_LIGHT]!,
        rem: stats[HealthDataType.SLEEP_REM]!,
      );
    }).toList();

    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }
}
