import 'package:flutter/material.dart';

extension OnlyDate on DateTime {
  DateTime get onlyDate => DateTime(year, month, day);

  bool isInsideInterval(DateTime start, DateTime end) {
    return !isBefore(start) && !isAfter(end);
  }
}

class DateKey extends ValueKey<DateTime> {
  DateKey(DateTime date) : super(date.onlyDate);

  int compareTo(DateKey other) => value.compareTo(other.value);
}

extension Coverage on DateTimeRange {
  /// Проверяет, покрывает ли интервал [other] текущий интервал ПОЛНОСТЬЮ
  bool isFullyCoveredBy(DateTimeRange other) {
    return (start.isAfter(other.start) || start.isAtSameMomentAs(other.start)) &&
        (end.isBefore(other.end) || end.isAtSameMomentAs(other.end));
  }

  /// Возвращает ОДИН интервал, который полностью закроет непокрытые участки.
  /// Если текущий интервал полностью покрыт, возвращает null.
  DateTimeRange? getUncoveredRange(DateTimeRange other) {
    // Сценарий 0: Полное покрытие -> ничего закрывать не надо
    if (isFullyCoveredBy(other)) return null;

    // Сценарий 1: Интервалы вообще не пересекаются
    final overlaps = start.isBefore(other.end) && end.isAfter(other.start);
    if (!overlaps) return this;

    // Сценарий 2: Пересечение есть, но покрытие частичное.
    // Непокрытый старт: если наш start левее other.start — берём наш start,
    // иначе непокрытая часть начинается там, где other закончился.
    final uncStart = start.isBefore(other.start) ? start : other.end;
    // Непокрытый конец: если наш end правее other.end — берём наш end,
    // иначе непокрытая часть заканчивается там, где other начался.
    final uncEnd = end.isAfter(other.end) ? end : other.start;

    // Защита от некорректного диапазона
    if (!uncStart.isBefore(uncEnd)) return null;

    return DateTimeRange(start: uncStart, end: uncEnd);
  }
}

extension DateListExtension on Iterable<DateKey> {
  DateKey get earliestDate =>
      fold(DateKey(DateTime.now()), (prev, next) => prev.value.isBefore(next.value) ? prev : next);
  DateKey get latestDate =>
      fold(DateKey(DateTime.now()), (prev, next) => prev.value.isAfter(next.value) ? prev : next);
}
