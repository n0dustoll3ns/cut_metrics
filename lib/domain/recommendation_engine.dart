import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/weight_day.dart';

/// Статус темпа снижения веса (спека Фазы 5, A.3).
enum PaceStatus { inPace, tooSlow, tooFast }

/// Результат еженедельного саммари.
///
/// Вместо `DateTimeRange` (dart:ui, конфликтует с «чистый Dart без Flutter») —
/// поля [rangeStart]/[rangeEnd]. Добавлены [weightChangeKg] (для «±N кг за неделю»)
/// и [conclusionText] (вывод-строка по макету саммари).
class WeeklySummary {
  /// Начало окна (первая EMA-точка в окне, не обязательно ровно today−6).
  final DateTime rangeStart;

  /// Конец окна (последняя EMA-точка в окне).
  final DateTime rangeEnd;

  /// Фактический темп, %/нед (нормализован к 7 дням, может быть со знаком).
  final double actualPacePercent;

  /// Целевой темп, %/нед (положительное число).
  final double targetPacePercent;

  /// Изменение сглаженного веса за окно, кг (со знаком).
  final double weightChangeKg;

  final PaceStatus status;

  /// Вывод-строка («Вес снижается стабильно…»).
  final String conclusionText;

  /// Рекомендация на следующую неделю.
  final String recommendationText;

  const WeeklySummary({
    required this.rangeStart,
    required this.rangeEnd,
    required this.actualPacePercent,
    required this.targetPacePercent,
    required this.weightChangeKg,
    required this.status,
    required this.conclusionText,
    required this.recommendationText,
  });

  @override
  String toString() =>
      'WeeklySummary($rangeStart..$rangeEnd, pace: $actualPacePercent%/'
      '$targetPacePercent%, kg: $weightChangeKg, status: $status)';
}

/// Ядро продукта: сравнение фактического темпа изменения веса с целевым.
///
/// **Чистый Dart** — без импортов Flutter/Health Connect (DoD A.8 п.1).
/// Принимает уже резолвленный кеш весов и предрассчитанный EMA-кеш —
/// сам никаких запросов не делает.
///
/// Алгоритм (A.3 с уточнением от 2026-08-21):
/// 1. Окно — последние 7 дней от [today] (скользящее).
/// 2. Берём EMA-точки, попавшие в окно; start = первая, end = последняя.
/// 3. `rawPct = (EMA(end) − EMA(start)) / EMA(start) × 100`, нормализация к неделе:
///    `actualPacePercent = rawPct × 7 / daysBetween` (минимум 1 день между точками).
/// 4. Статус по |actual| vs target ± [RecommendationConfig.paceTolerance].
/// 5. Текст — шаблон из [RecommendationConfig] с подстановкой чисел.
class RecommendationEngine {
  const RecommendationEngine._();

  /// Считает саммари. Возвращает `null`, если данных недостаточно:
  /// в окне меньше [minPoints] сырых точек веса (по умолчанию 3).
  static WeeklySummary? compute({
    required Map<DateKey, WeightDay> weightCache,
    required Map<DateKey, WeightDay> emaCache,
    required DateTime today,
    required double targetPacePercent,
    double tolerance = RecommendationConfig.paceTolerance,
    int minPoints = RecommendationConfig.minWeightPointsInWindow,
  }) {
    final windowStart = DateKey(today.subtract(const Duration(days: 6)));
    final windowEnd = DateKey(today);

    bool inWindow(DateKey k) =>
        !k.value.isBefore(windowStart.value) && !k.value.isAfter(windowEnd.value);

    // Достаточность: сырые точки веса в окне.
    final rawInWindow = weightCache.keys.where(inWindow).length;
    if (rawInWindow < minPoints) return null;

    // EMA-точки в окне, отсортированные по дате.
    final emaPoints = emaCache.values.where((e) => inWindow(e.date)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (emaPoints.length < 2) return null;

    final first = emaPoints.first;
    final last = emaPoints.last;
    if (first.weight <= 0) return null;

    final rawPct = (last.weight - first.weight) / first.weight * 100;
    final daysBetween =
        last.date.value.difference(first.date.value).inDays.clamp(1, 7).toDouble();
    final actualPace = rawPct * 7 / daysBetween;

    final status = _statusFor(actualPace.abs(), targetPacePercent, tolerance);

    return WeeklySummary(
      rangeStart: first.date.value,
      rangeEnd: last.date.value,
      actualPacePercent: actualPace,
      targetPacePercent: targetPacePercent,
      weightChangeKg: last.weight - first.weight,
      status: status,
      conclusionText: _conclusionFor(status),
      recommendationText: _recommendationFor(status, actualPace, targetPacePercent),
    );
  }

  /// A.3: сравнение |actual| с target с допуском.
  static PaceStatus _statusFor(double absActual, double target, double tolerance) {
    final diff = absActual - target;
    if (diff.abs() <= tolerance) return PaceStatus.inPace;
    return diff < 0 ? PaceStatus.tooSlow : PaceStatus.tooFast;
  }

  static String _conclusionFor(PaceStatus status) => switch (status) {
        PaceStatus.inPace => RecommendationConfig.conclusionInPace,
        PaceStatus.tooSlow => RecommendationConfig.conclusionTooSlow,
        PaceStatus.tooFast => RecommendationConfig.conclusionTooFast,
      };

  static String _recommendationFor(PaceStatus status, double actual, double target) {
    final template = switch (status) {
      PaceStatus.inPace => RecommendationConfig.recInPace,
      PaceStatus.tooSlow => RecommendationConfig.recTooSlow,
      PaceStatus.tooFast => RecommendationConfig.recTooFast,
    };
    return template
        .replaceAll('{actual}', actual.abs().toStringAsFixed(1))
        .replaceAll('{target}', target.toStringAsFixed(1));
  }
}
