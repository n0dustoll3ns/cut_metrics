/// Ключ даты, нормализованный до начала дня (полночь).
///
/// Используется как ключ в Map для группировки записей по дням.
/// Сравнение и хеш — по нормализованному [DateTime], поэтому две записи
/// в один день (но в разное время) получают одинаковый ключ.
class DateKey implements Comparable<DateKey> {
  DateKey(DateTime date) : value = DateTime(date.year, date.month, date.day);

  /// Нормализованное значение (полночь).
  final DateTime value;

  /// Начало дня (полночь) — удобно для передачи в Health Connect API.
  DateTime get startOfDay => value;

  /// Конец дня (23:59:59.999) — для интервальных запросов в Health Connect.
  DateTime get endOfDay =>
      value.add(const Duration(hours: 23, minutes: 59, seconds: 59, milliseconds: 999));

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