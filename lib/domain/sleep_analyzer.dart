import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/sleep_day.dart';
import 'package:health/health.dart';

/// Анализ сырых интервалов сна → [SleepDay] по ночам.
///
/// Перенесён из `lib/old_proj/domain/sleep.dart` (разрешение пользователя, С1,
/// 2026-08-21) с адаптациями Фазы 5:
/// 1. Убран `sourcePriorities` — в новой архитектуре приоритетов источников сна нет.
/// 2. Добавлен `SLEEP_ASLEEP` с приоритетом: если за ночь есть общая длительность
///    (`SLEEP_ASLEEP`), она становится [SleepDay.total], иначе — сумма стадий (С2).
/// 3. Merge интервалов выполняется ПО СЛОЯМ: стадии (DEEP/LIGHT/REM) отдельно от
///    `SLEEP_ASLEEP` — общий интервал сна содержит стадии внутри, сквозной merge
///    обрезал бы стадии (overwrite-логика).
/// 4. Возвращает только ночи с `total > 0` — пустые ночи не попадают в кеш (С4).
///
/// Правило дня сна (С3, без изменений из старого кода): интервал, начавшийся
/// после 12:00, относится к следующему дню (ночь 23:00→07:00 = день, в который
/// наступило утро).
///
/// ⚠️ Чистая синхронная функция — работает с предзагруженными точками
/// (аналогично `HealthDataProcessor`).
class SleepAnalyzer {
  /// Стадии сна, которые суммируются при отсутствии `SLEEP_ASLEEP`.
  static const Set<HealthDataType> _stageTypes = {
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
  };

  /// Общая длительность сна от трекера — приоритетна над суммой стадий (С2).
  static const Set<HealthDataType> _asleepTypes = {
    HealthDataType.SLEEP_ASLEEP,
  };

  /// Анализирует сырые точки за диапазон и возвращает ночи с данными.
  ///
  /// [rangeStart]/[rangeEnd] — границы диапазона по «дням сна» (не по датам
  /// интервалов): ночь, начавшаяся 23:00 последнего дня диапазона, относится
  /// к следующему дню и отфильтруется. Диапазон читается с запасом −1 день —
  /// об этом заботится вызывающий код (ViewModel).
  Map<DateKey, SleepDay> analyze({
    required List<HealthDataPoint> rawPoints,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    // 1. Конвертация в интервалы (только tracked-типы с положительной длительностью).
    final allIntervals = rawPoints
        .where((p) => _stageTypes.contains(p.type) || _asleepTypes.contains(p.type))
        .where((p) => p.dateTo.isAfter(p.dateFrom))
        .map((p) => _SleepInterval(
              start: p.dateFrom,
              end: p.dateTo,
              type: p.type,
            ))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // 2. Merge по слоям: стадии отдельно, ASLEEP отдельно.
    final merged = <_SleepInterval>[
      ..._mergeIntervals(allIntervals.where((i) => _stageTypes.contains(i.type)).toList()),
      ..._mergeIntervals(allIntervals.where((i) => _asleepTypes.contains(i.type)).toList()),
    ];

    // 3. Агрегация по «дням сна».
    final rangeStartKey = DateKey(rangeStart);
    final rangeEndKey = DateKey(rangeEnd);

    final byDay = <DateKey, Map<HealthDataType, double>>{};
    for (final interval in merged) {
      final key = _sleepDayOf(interval.start);
      if (key.value.isBefore(rangeStartKey.value) || key.value.isAfter(rangeEndKey.value)) {
        continue;
      }
      final hours = interval.end.difference(interval.start).inMinutes / 60.0;
      byDay.putIfAbsent(key, () => {}).update(
            interval.type,
            (v) => v + hours,
            ifAbsent: () => hours,
          );
    }

    // 4. Сборка — только ночи с total > 0.
    final result = <DateKey, SleepDay>{};
    for (final entry in byDay.entries) {
      final stats = entry.value;
      final day = SleepDay(
        date: entry.key,
        deep: stats[HealthDataType.SLEEP_DEEP] ?? 0,
        light: stats[HealthDataType.SLEEP_LIGHT] ?? 0,
        rem: stats[HealthDataType.SLEEP_REM] ?? 0,
        asleep: stats[HealthDataType.SLEEP_ASLEEP] ?? 0,
      );
      if (day.total > 0) result[entry.key] = day;
    }
    return result;
  }

  /// «День сна»: интервал после 12:00 относится к следующему дню (С3).
  DateKey _sleepDayOf(DateTime start) {
    final target = start.hour >= 12 ? start.add(const Duration(days: 1)) : start;
    return DateKey(target);
  }

  /// Слияние пересекающихся интервалов одного слоя, «последний побеждает»
  /// (overwrite logic из старого кода, без изменений).
  List<_SleepInterval> _mergeIntervals(List<_SleepInterval> intervals) {
    final result = <_SleepInterval>[];

    for (final current in intervals) {
      if (result.isEmpty) {
        result.add(current);
        continue;
      }

      final last = result.last;

      if (current.start.isBefore(last.end)) {
        // Пересечение: обрезаем предыдущий по началу текущего.
        if (current.start.isAfter(last.start)) {
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
}

/// Иммутабельный интервал сна (перенос из old_proj).
class _SleepInterval {
  final DateTime start;
  final DateTime end;
  final HealthDataType type;

  const _SleepInterval({
    required this.start,
    required this.end,
    required this.type,
  });

  _SleepInterval withEnd(DateTime newEnd) =>
      _SleepInterval(start: start, end: newEnd, type: type);
}
