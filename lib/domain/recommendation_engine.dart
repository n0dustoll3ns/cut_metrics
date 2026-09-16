import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/gap_rule.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/domain/weekly_energy_stats.dart';

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
  ///
  /// [energyStats] (Фаза 7, C.2): энергостаты за скользящее окно. При
  /// `null` (или null-знаменателях) — тексты Фазы 5 дословно (регресс);
  /// при наличии — тексты v2 из `ExpenditureConfig` с конкретными ккал
  /// и динамической дельтой (§0 п. 13).
  static WeeklySummary? compute({
    required Map<DateKey, WeightDay> weightCache,
    required Map<DateKey, WeightDay> emaCache,
    required DateTime today,
    required double targetPacePercent,
    WeeklyEnergyStats? energyStats,
    double tolerance = RecommendationConfig.paceTolerance,
    int minPoints = RecommendationConfig.minWeightPointsInWindow,
  }) {
    final windowStart = DateKey(today.subtract(const Duration(days: 6)));
    final windowEnd = DateKey(today);

    bool inWindow(DateKey k) =>
        !k.value.isBefore(windowStart.value) && !k.value.isAfter(windowEnd.value);

    // Правило «после последнего 5+-дневного разрыва» (2026-09-16): в расчёте
    // темпа имеют смысл только EMA-точки после последнего длительного
    // пропуска взвешиваний (EMA-точка есть на каждом дне взвешивания — это же
    // достаточность по сырым точкам последнего сегмента; при точках меньше
    // minPoints саммари не готово — «данных недостаточно»).
    final emaSorted = emaCache.values.where((e) => inWindow(e.date)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final keptDays = daysAfterLastGap(emaSorted.map((e) => e.date));
    final emaPoints = emaSorted.where((e) => keptDays.contains(e.date)).toList();
    if (emaPoints.length < minPoints) return null;

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
      recommendationText: _recommendationFor(
        status,
        actualPace,
        targetPacePercent,
        weightCache: weightCache,
        today: today,
        energyStats: energyStats,
      ),
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

  /// Текст рекомендации: v2 (с энергостатами и конкретными ккал, C.2) или
  /// дословные тексты Фазы 5 при отсутствии данных.
  static String _recommendationFor(
    PaceStatus status,
    double actual,
    double target, {
    required Map<DateKey, WeightDay> weightCache,
    required DateTime today,
    WeeklyEnergyStats? energyStats,
  }) {
    // v2: нужен вес (для дельты) и — для «в темпе» — средний баланс.
    final weight = _latestWeightUpTo(weightCache, today);
    if (energyStats != null && weight != null) {
      final needsBalance = status == PaceStatus.inPace;
      if (!needsBalance || energyStats.avgBalance != null) {
        return _recommendationV2(status, actual, target, weight, energyStats);
      }
    }

    // Фаза 5 — дословно (регресс).
    final template = switch (status) {
      PaceStatus.inPace => RecommendationConfig.recInPace,
      PaceStatus.tooSlow => RecommendationConfig.recTooSlow,
      PaceStatus.tooFast => RecommendationConfig.recTooFast,
    };
    return template
        .replaceAll('{actual}', actual.abs().toStringAsFixed(1))
        .replaceAll('{target}', target.toStringAsFixed(1));
  }

  /// v2 (§0 п. 13): динамическая дельта `вес × |цель−факт| × 11` (коридор
  /// 50–300, округление до 10), `{intakeNew} = {intake} ∓ {delta}`. Числа
  /// прихода/баланса — «как есть» (решение пользователя 2026-09-14:
  /// округляется только дельта).
  static String _recommendationV2(
    PaceStatus status,
    double actual,
    double target,
    double weightKg,
    WeeklyEnergyStats stats,
  ) {
    final delta = ExpenditureConfig.recommendationDeltaKcal(weightKg, actual, target);
    final intake = stats.avgIntake;
    final intakeNew = status == PaceStatus.tooFast ? intake + delta : intake - delta;

    final template = switch (status) {
      PaceStatus.inPace => ExpenditureConfig.recInPaceV2,
      PaceStatus.tooSlow => ExpenditureConfig.recTooSlowV2,
      PaceStatus.tooFast => ExpenditureConfig.recTooFastV2,
    };

    return template
        .replaceAll('{actual}', actual.abs().toStringAsFixed(1))
        .replaceAll('{target}', target.toStringAsFixed(1))
        .replaceAll('{balance}', _formatKcalSigned(stats.avgBalance ?? 0))
        .replaceAll('{intake}', _formatKcal(intake))
        .replaceAll('{intakeNew}', _formatKcal(intakeNew))
        .replaceAll('{delta}', delta.toString());
  }

  /// Последний резолвленный вес ≤ today (для дельты v2); fallback — последний.
  static double? _latestWeightUpTo(
      Map<DateKey, WeightDay> weightCache, DateTime today) {
    if (weightCache.isEmpty) return null;
    final sorted = weightCache.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    WeightDay? result;
    for (final w in sorted) {
      if (w.date.value.isAfter(today)) break;
      result = w;
    }
    return result?.weight ?? sorted.last.weight;
  }

  /// Ккал «как есть»: целое — целым, дробное — 1 знак (без округления до 10).
  static String _formatKcal(double v) {
    final r = v.roundToDouble();
    return v == r ? r.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  /// Ккал со знаком: «−530» / «+120» / «0».
  static String _formatKcalSigned(double v) {
    if (v == 0) return '0';
    return v < 0 ? '−${_formatKcal(v.abs())}' : '+${_formatKcal(v)}';
  }
}
