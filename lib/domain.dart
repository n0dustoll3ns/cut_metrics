class SleepDay {
  final DateTime date;
  final double deep;
  final double light;
  final double rem;

  const SleepDay({required this.date, required this.deep, required this.light, required this.rem})
    : total = deep + light + rem;

  final double total;

  @override
  String toString() =>
      '\nSleepDay ${date.day}.${date.month}: deep = ${deep.toStringAsFixed(2)}; total = ${total.toStringAsFixed(2)}';
}
