import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';

/// Модель данных для дня с шагами.
///
/// Поле [source] указывает, откуда взялось итоговое значение после резолюции
/// приоритета источников (Tier 1 → Tier 2) — см. `HealthDataProcessor`.
///
/// [sourcePackage] (Фаза 6, C.2) — пакет приложения-источника итогового
/// значения: наш пакет для `manual`, пакет внешнего приложения для `external`
/// (шаги «Авто» — источник с максимальной суммой за день).
class StepsDay {
  final DateKey date;
  final int steps;
  final DataSource source;
  final String? sourcePackage;

  StepsDay({
    required this.date,
    required this.steps,
    required this.source,
    this.sourcePackage,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepsDay &&
          date == other.date &&
          steps == other.steps &&
          source == other.source &&
          sourcePackage == other.sourcePackage;

  @override
  int get hashCode => Object.hash(date, steps, source, sourcePackage);

  @override
  String toString() =>
      'StepsDay(date: $date, steps: $steps, source: $source, '
      'sourcePackage: $sourcePackage)';
}