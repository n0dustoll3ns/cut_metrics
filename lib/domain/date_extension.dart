import 'package:flutter/material.dart';

extension OnlyDate on DateTime {
  DateTime get onlyDate => DateTime(year, month, day);

  bool isInsideInterval(DateTime start, DateTime end) {
    return isAfter(start) && isBefore(end);
  }
}

class DateKey extends ValueKey<DateTime> {
  DateKey(DateTime date) : super(date.onlyDate);

  int compareTo(DateKey other) => value.compareTo(other.value);
}

extension Coverage on DateTimeRange {
  /// Проверяет, покрывает ли интервал [other] текущий интервал ПОЛНОСТЬЮ
  bool isFullyCoveredBy(DateTimeRange other) {
    // Текущий старт должен быть равен или позже старта другого,
    // а текущий конец — равен или раньше конца другого.
    return (start.isAfter(other.start) || start.isAtSameMomentAs(other.start)) &&
        (end.isBefore(other.end) || end.isAtSameMomentAs(other.end));
  }

  /// Возвращает ОДИН интервал, который полностью закроет непокрытые участки.
  /// Если текущий интервал полностью покрыт, возвращает null.
  DateTimeRange? getUncoveredRange(DateTimeRange other) {
    // Сценарий 0: Полное покрытие -> ничего закрывать не надо
    if (isFullyCoveredBy(other)) {
      return null;
    }

    // Сценарий 1: Интервалы вообще не пересекаются
    // Непокрытая часть — это весь наш первый интервал
    final overlaps = start.isBefore(other.end) && end.isAfter(other.start);
    if (!overlaps) {
      return this;
    }

    // Сценарий 2: Пересечение есть, но покрытие частичное.
    // Нам нужно определить крайние точки «непокрытости».

    // Если второй интервал начался позже первого, значит остался «хвост» в начале
    final leftUncovered = start.isBefore(other.start);
    // Если второй интервал закончился раньше первого, значит остался «хвост» в конце
    final rightUncovered = end.isAfter(other.end);

    final DateTime newStart = leftUncovered ? start : other.end;
    final DateTime newEnd = rightUncovered ? end : other.start;

    return DateTimeRange(start: newStart, end: newEnd);
  }
}

extension DateListExtension on Iterable<DateKey> {
  DateKey get earliestDate =>
      fold(DateKey(DateTime.now()), (prev, next) => prev.value.isBefore(next.value) ? prev : next);
  DateKey get latestDate =>
      fold(DateKey(DateTime.now()), (prev, next) => prev.value.isAfter(next.value) ? prev : next);
}
