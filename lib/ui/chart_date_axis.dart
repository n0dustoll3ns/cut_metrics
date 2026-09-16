import 'package:cut_metrics/ui/months.dart';

/// Ось дат Фазы 6 (A3, `test_report_26-09-02.md`) — общая для графиков
/// веса (LineChart) и энергобаланса (BarChart, Фаза 7 B.1).
///
/// - Обычный день — только число («7»), Space Mono 10px, Noise Grey
///   (стиль задаёт потребитель).
/// - Граница месяца — «1 АВГ» (число + 3-буквенный месяц uppercase, жирнее).
///   Показывается ВСЕГДА, даже вне шага прореживания — вытесняет ближайшую
///   обычную метку.
/// - Прореживание: не более ~8 меток (шаг = ceil(точек / 7)).
///
/// Возвращает карту «индекс → текст» и множество индексов-границ месяца
/// (для тонкой вертикальной линии сетки на границе, outline 1px).
class ChartDateAxisData {
  final Map<int, String> labels;
  final Set<int> monthBoundaries;

  const ChartDateAxisData(this.labels, this.monthBoundaries);
}

ChartDateAxisData computeChartDateAxis(List<DateTime> dates) {
  final n = dates.length;
  if (n == 0) return const ChartDateAxisData({}, {});

  final step = (n / 7).ceil().clamp(1, n);
  final regular = <int>{};
  for (var i = 0; i < n; i += step) {
    regular.add(i);
  }

  final labels = <int, String>{};
  final boundaries = <int>{};
  for (var i = 0; i < n; i++) {
    if (dates[i].day == 1) boundaries.add(i);
  }

  // Граница месяца: метка «1 АВГ» всегда (даже вне шага); ближайшая обычная
  // вытесняется, чтобы соседние надписи не слипались.
  for (final i in boundaries) {
    final d = dates[i];
    labels[i] = '1 ${kMonthsShort[d.month - 1].toUpperCase()}';
    if (regular.contains(i - 1)) {
      regular.remove(i - 1);
    } else if (regular.contains(i + 1)) {
      regular.remove(i + 1);
    }
    regular.remove(i);
  }
  for (final i in regular) {
    if (!labels.containsKey(i)) {
      labels[i] = '${dates[i].day}';
    }
  }
  return ChartDateAxisData(labels, boundaries);
}

/// Полная дата для тултипа: «17 июл» (день + 3-буквенный месяц).
String chartTooltipDate(DateTime date) =>
    '${date.day} ${kMonthsShort[date.month - 1]}';
