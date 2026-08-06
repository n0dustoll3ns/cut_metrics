import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';

/// Модель данных для дня с весом.
///
/// Поле [source] указывает, откуда взялось итоговое значение после резолюции
/// приоритета источников (Tier 1 → Tier 2) — см. `HealthDataProcessor`.
class WeightDay {
  final DateKey date;
  final double weight; // вес в кг
  final DataSource source;

  WeightDay({
    required this.date,
    required this.weight,
    required this.source,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeightDay &&
          date == other.date &&
          weight == other.weight &&
          source == other.source;

  @override
  int get hashCode => Object.hash(date, weight, source);

  @override
  String toString() =>
      'WeightDay(date: $date, weight: $weight, source: $source)';
}