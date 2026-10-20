import 'package:cut_metrics/domain/calc_trace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тесты моделей трассы «Как рассчитано» (CalcDetail §2):
/// равенство/хэш (паттерн доменных моделей), дефолты, immutable-значения.
void main() {
  group('TraceInput', () {
    const a = TraceInput(
      label: 'Шаги за 15 января — com.samsung',
      valueText: '8 000',
      kind: TraceSourceKind.healthConnect,
      recordsText: '2 000 + 4 500 + 1 500',
    );
    const b = TraceInput(
      label: 'Шаги за 15 января — com.samsung',
      valueText: '8 000',
      kind: TraceSourceKind.healthConnect,
      recordsText: '2 000 + 4 500 + 1 500',
    );

    test('равенство по всем полям', () {
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('различие по любому полю', () {
      expect(a, isNot(equals(const TraceInput(label: 'x', valueText: '8 000', kind: TraceSourceKind.healthConnect))));
      expect(a, isNot(equals(TraceInput(label: a.label, valueText: '9 000', kind: a.kind))));
      expect(a, isNot(equals(const TraceInput(label: 'l', valueText: 'v', kind: TraceSourceKind.manual))));
      expect(a, isNot(equals(TraceInput(label: 'l', valueText: 'v', kind: TraceSourceKind.healthConnect, sourceName: 's'))));
      expect(a, isNot(equals(const TraceInput(label: 'l', valueText: 'v', kind: TraceSourceKind.healthConnect, note: 'n'))));
      expect(a, isNot(equals(const TraceInput(label: 'l', valueText: 'v', kind: TraceSourceKind.healthConnect, notUsed: true, notUsedReason: 'сумма меньше'))));
    });

    test('дефолты: notUsed = false, пометки null', () {
      expect(a.notUsed, false);
      expect(a.sourceName, isNull);
      expect(a.note, isNull);
      expect(a.notUsedReason, isNull);
    });
  });

  group('TraceStep', () {
    test('равенство и хэш', () {
      const a = TraceStep(title: 'Сумма', formulaText: '1 + 2', resultText: '= 3', note: 'n');
      const b = TraceStep(title: 'Сумма', formulaText: '1 + 2', resultText: '= 3', note: 'n');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(const TraceStep(title: 'Сумма'), isNot(equals(a)));
    });
  });

  group('TraceDayRow / TraceEmaRow', () {
    test('TraceDayRow: равенство, доп-колонки по дефолту null', () {
      const a = TraceDayRow(dateText: '15 января', valueText: '8 000', sourceName: 's');
      const b = TraceDayRow(dateText: '15 января', valueText: '8 000', sourceName: 's');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.value2Text, isNull);
      expect(a.value3Text, isNull);
      expect(
        a,
        isNot(equals(const TraceDayRow(dateText: '15 января', valueText: '8 000', value2Text: '2 350'))),
      );
    });

    test('TraceEmaRow: рестарт серии по умолчанию false, равенство', () {
      const a = TraceEmaRow(dateText: '15 января', rawWeight: 84.0, ema: 84.1);
      const b = TraceEmaRow(dateText: '15 января', rawWeight: 84.0, ema: 84.1);
      const r = TraceEmaRow(dateText: '16 января', rawWeight: 84.0, ema: 84.0, seriesRestart: true);
      expect(a, b);
      expect(a.seriesRestart, false);
      expect(r, isNot(equals(a)));
      expect(r.hashCode, isNot(a.hashCode));
    });
  });

  group('CalcTrace', () {
    const t1 = CalcTrace(
      title: 'Шаги',
      subtitle: '15 января',
      inputs: [TraceInput(label: 'l', valueText: 'v', kind: TraceSourceKind.formula)],
      steps: [TraceStep(title: 's', resultText: 'r')],
      resultText: '8 000',
      resultUnit: 'шагов',
    );
    final t2 = CalcTrace(
      title: 'Шаги',
      subtitle: '15 января',
      inputs: [const TraceInput(label: 'l', valueText: 'v', kind: TraceSourceKind.formula)],
      steps: const [TraceStep(title: 's', resultText: 'r')],
      resultText: '8 000',
      resultUnit: 'шагов',
    );

    test('равенство по содержимому (включая списки)', () {
      expect(t1, t2);
      expect(t1.hashCode, t2.hashCode);
    });

    test('дефолты: dayRows/emaRows null, не свёрнуто', () {
      expect(t1.dayRows, isNull);
      expect(t1.emaRows, isNull);
      expect(t1.dayRowsCollapsedByDefault, false);
      expect(t1.resultNote, isNull);
    });

    test('различие в списках даёт неравенство', () {
      final t3 = CalcTrace(
        title: 'Шаги',
        subtitle: '15 января',
        inputs: const [TraceInput(label: 'l2', valueText: 'v', kind: TraceSourceKind.formula)],
        steps: const [TraceStep(title: 's', resultText: 'r')],
        resultText: '8 000',
      );
      expect(t1, isNot(equals(t3)));
    });

    test('toString содержит заголовок и итог', () {
      expect(t1.toString(), contains('Шаги'));
      expect(t1.toString(), contains('8 000'));
    });
  });
}
