import 'package:cut_metrics/domain/date_key.dart';

/// Модель данных для ночи сна.
///
/// [total] — итоговая длительность: [asleep] (если трекер пишет общую
/// длительность `SLEEP_ASLEEP`), иначе сумма стадий deep+light+rem.
/// Ночи без данных не попадают в кеш (Фаза 5, решение С4 — исключать из среднего).
class SleepDay {
  final DateKey date;
  final double deep;
  final double light;
  final double rem;

  /// Часы `SLEEP_ASLEEP` (общая длительность от трекера), 0 если трекер
  /// пишет только стадии.
  final double asleep;

  /// Часы `SLEEP_ASLEEP`, если > 0, иначе сумма стадий.
  final double total;

  const SleepDay({
    required this.date,
    required this.deep,
    required this.light,
    required this.rem,
    required this.asleep,
  }) : total = asleep > 0 ? asleep : deep + light + rem;

  @override
  String toString() =>
      'SleepDay(date: $date, deep: ${deep.toStringAsFixed(2)}, '
      'light: ${light.toStringAsFixed(2)}, rem: ${rem.toStringAsFixed(2)}, '
      'asleep: ${asleep.toStringAsFixed(2)}, total: ${total.toStringAsFixed(2)})';
}
