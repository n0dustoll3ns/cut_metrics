import 'package:cut_metrics/domain/date_extension.dart';

class SleepDay {
  final DateKey date;
  final double deep;
  final double light;
  final double rem;

  const SleepDay({required this.date, required this.deep, required this.light, required this.rem})
    : total = deep + light + rem;

  final double total;

  @override
  String toString() =>
      '\nSleepDay ${date.value.day}.${date.value.month}: deep = ${deep.toStringAsFixed(2)}; total = ${total.toStringAsFixed(2)}';
}

// Модель данных для дня с шагами
class StepsDay {
  final DateKey date;
  final int steps; // вес в кг

  const StepsDay({required this.date, required this.steps});

  StepsDay copyWithAddedSteps({required int steps}) {
    return StepsDay(date: date, steps: steps + this.steps);
  }
}

String getMonthTitle(int number) =>
    const ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'][number];
