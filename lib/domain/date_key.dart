/// Ключ даты, нормализованный до начала дня (полночь).
///
/// Используется как ключ в Map для группировки записей по дням.
/// Сравнение и хеш — по нормализованному [DateTime], поэтому две записи
/// в один день (но в разное время) получают одинаковый ключ.
class DateKey implements Comparable<DateKey> {
  DateKey(DateTime date) : value = DateTime(date.year, date.month, date.day);

  /// Нормализованное значение (полночь).
  final DateTime value;

  @override
  int compareTo(DateKey other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is DateKey && value.isAtSameMomentAs(other.value);

  @override
  int get hashCode => Object.hash(value.year, value.month, value.day);

  @override
  String toString() =>
      'DateKey(${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')})';
}

/// Extension для нормализации [DateTime] до начала дня.
extension OnlyDate on DateTime {
  DateTime get onlyDate => DateTime(year, month, day);

  /// Включает границы интервала: `!isBefore(start) && !isAfter(end)`.
  bool isInsideInterval(DateTime start, DateTime end) {
    return !isBefore(start) && !isAfter(end);
  }
}