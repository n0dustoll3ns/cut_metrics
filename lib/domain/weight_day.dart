import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';

/// Модель данных для дня с весом.
///
/// Поле [source] указывает, откуда взялось итоговое значение после резолюции
/// приоритета источников (Tier 1 → Tier 2) — см. `HealthDataProcessor`.
///
/// [sourcePackage] (Фаза 6, C.2) — пакет приложения-источника итогового
/// значения: наш пакет для `manual`, пакет внешнего приложения для `external`.
/// `null` — источник неизвестен (EMA-точки, вычисляемые значения).
class WeightDay {
  final DateKey date;
  final double weight; // вес в кг
  final DataSource source;
  final String? sourcePackage;

  WeightDay({
    required this.date,
    required this.weight,
    required this.source,
    this.sourcePackage,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeightDay &&
          date == other.date &&
          weight == other.weight &&
          source == other.source &&
          sourcePackage == other.sourcePackage;

  @override
  int get hashCode => Object.hash(date, weight, source, sourcePackage);

  @override
  String toString() =>
      'WeightDay(date: $date, weight: $weight, source: $source, '
      'sourcePackage: $sourcePackage)';
}