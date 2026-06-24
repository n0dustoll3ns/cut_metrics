class SleepDay {
  final DateTime date;
  final double deep;
  final double light;
  final double rem;

  const SleepDay({
    required this.date,
    required this.deep,
    required this.light,
    required this.rem,
  }) : total = deep + light + rem;

  final double total;

  @override
  String toString() =>
      '\nSleepDay ${date.day}.${date.month}: deep = ${deep.toStringAsFixed(2)}; total = ${total.toStringAsFixed(2)}';
}

// Модель данных для дня с шагами
class StepsDay {
  final DateTime date;
  final int steps; // вес в кг

  StepsDay({required this.date, required this.steps});
}

String getMonthTitle(int number) => const [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
][number];
