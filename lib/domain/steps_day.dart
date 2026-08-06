import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';

/// Модель данных для дня с шагами.
///
/// Поле [source] указывает, откуда взялось итоговое значение после резолюции
/// приоритета источников (Tier 1 → Tier 2) — см. `HealthDataProcessor`.
class StepsDay {
  final DateKey date;
  final int steps;
  final DataSource source;

  StepsDay({
    required this.date,
    required this.steps,
    required this.source,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepsDay &&
          date == other.date &&
          steps == other.steps &&
          source == other.source;

  @override
  int get hashCode => Object.hash(date, steps, source);

  @override
  String toString() => 'StepsDay(date: $date, steps: $steps, source: $source)';
}