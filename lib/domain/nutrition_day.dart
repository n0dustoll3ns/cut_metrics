import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';

/// Модель данных для дня с питанием (Фаза 7, A.1).
///
/// Итог дня после резолюции «один источник на день» (A.6): [calories] — сумма
/// калорий записей победившего источника за день, макросы (г) — `null`, если
/// ни одна запись победителя не отдаёт макрос («нет данных ≠ 0»).
///
/// [source] — Tier 1 (наш «Итог дня», `manual`) или Tier 2 (`external`);
/// [sourcePackage] — пакет приложения-источника итогового значения (для беджа
/// и решений «Ок/Не ок», механика Фазы 6 B/C переиспользуется через
/// `MetricType.nutrition`).
class NutritionDay {
  final DateKey date;

  /// Ккал за день (сумма записей победившего источника).
  final double calories;

  /// Белок, г; `null` — источник не отдал ни одной записи с белком за день.
  final double? protein;

  /// Жиры, г; `null` — аналогично [protein].
  final double? fat;

  /// Углеводы, г; `null` — аналогично [protein].
  final double? carbs;

  final DataSource source;
  final String? sourcePackage;

  const NutritionDay({
    required this.date,
    required this.calories,
    required this.source,
    this.protein,
    this.fat,
    this.carbs,
    this.sourcePackage,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutritionDay &&
          date == other.date &&
          calories == other.calories &&
          protein == other.protein &&
          fat == other.fat &&
          carbs == other.carbs &&
          source == other.source &&
          sourcePackage == other.sourcePackage;

  @override
  int get hashCode =>
      Object.hash(date, calories, protein, fat, carbs, source, sourcePackage);

  @override
  String toString() =>
      'NutritionDay(date: $date, calories: ${calories.toStringAsFixed(0)}, '
      'Б:${protein?.toStringAsFixed(0) ?? '—'} '
      'Ж:${fat?.toStringAsFixed(0) ?? '—'} '
      'У:${carbs?.toStringAsFixed(0) ?? '—'}, '
      'source: $source, sourcePackage: $sourcePackage)';
}
