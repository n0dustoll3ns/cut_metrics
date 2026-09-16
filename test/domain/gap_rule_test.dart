import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/gap_rule.dart';
import 'package:flutter_test/flutter_test.dart';

/// Правило «после последнего 5+-дневного разрыва» (2026-09-16): для
/// средних имеют смысл только данные после последнего пропуска 5+ ПОДРЯД
/// дней; по каждой метрике отдельно. См. daysAfterLastGap.
void main() {
  DateKey d(String iso) => DateKey(DateTime.parse(iso));

  test('без разрывов — все дни', () {
    final days = ['2026-01-01', '2026-01-02', '2026-01-03'].map(d);
    expect(daysAfterLastGap(days), days.toSet());
  });

  test('пропуск 4 дня — разрыва нет', () {
    final days = ['2026-01-01', '2026-01-06'].map(d); // 4 пустых дня
    expect(daysAfterLastGap(days), days.toSet());
  });

  test('пропуск 5 дней — только дни после разрыва', () {
    final result = daysAfterLastGap(
      ['2026-01-01', '2026-01-02', '2026-01-08', '2026-01-09'].map(d),
    );
    expect(result, {d('2026-01-08'), d('2026-01-09')});
  });

  test('несколько разрывов — после последнего', () {
    final result = daysAfterLastGap(
      ['2026-01-01', '2026-01-10', '2026-01-11', '2026-01-25', '2026-01-26'].map(d),
    );
    // Разрывы: 8 дней (1-е → 10-е) и 13 дней (11-е → 25-е).
    expect(result, {d('2026-01-25'), d('2026-01-26')});
  });

  test('пустой ввод', () {
    expect(daysAfterLastGap(const []), isEmpty);
  });

  test('порог настраивается (gapDays)', () {
    final result = daysAfterLastGap(
      ['2026-01-01', '2026-01-04'].map(d), // 2 пустых дня
      gapDays: 2,
    );
    expect(result, {d('2026-01-04')});
  });
}
