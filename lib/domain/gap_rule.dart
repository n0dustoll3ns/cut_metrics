import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';

/// Правило «после последнего длительного разрыва» (2026-09-16): для
/// расчёта средних имеют смысл только данные, внесённые после последнего
/// пропуска [RecommendationConfig.emaBreakGapDays] (5) и более ПОДРЯД
/// дней — данные до длительного перерыва нерепрезентативны (отпуск,
/// болезнь, перерыв в трекинге). Работает в рамках каждой метрики
/// ОТДЕЛЬНО: шаги отсекаются по пропускам шагов, питание — по питанию и
/// т.д.
///
/// Согласовано с разрывом EMA в `HealthDataProcessor.computeEma` — тот же
/// порог и тот же смысл. Графики при этом показывают ВСЕ сегменты
/// (разрывы видны как разрывы линии EMA), правило касается только
/// расчётов: среднесуточные на Тренде, энергостаты, движок саммари
/// (при точках меньше minPoints после отсечения — «данных недостаточно»).
Set<DateKey> daysAfterLastGap(
  Iterable<DateKey> days, {
    int gapDays = RecommendationConfig.emaBreakGapDays,
  }) {
  final sorted = days.toList()..sort();
  if (sorted.isEmpty) return {};

  // Первый день после последнего разрыва: gapDays+ пустых дней подряд.
  var cutoff = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i].value.difference(sorted[i - 1].value).inDays - 1;
    if (gap >= gapDays) cutoff = sorted[i];
  }
  return sorted.where((d) => d.compareTo(cutoff) >= 0).toSet();
}
