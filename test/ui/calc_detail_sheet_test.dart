import 'package:cut_metrics/domain/calc_trace.dart';
import 'package:cut_metrics/ui/calc_detail_sheet.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Виджет-тесты листа «Как рассчитано» (CalcDetail §7 ТЗ): чекбокс
/// конкурентов, свёрнутая таблица дней, кнопка раскрытия цепочки EMA.
void main() {
  CalcTrace buildTrace({
    bool collapsedDays = false,
    int dayCount = 6,
  }) {
    return CalcTrace(
      title: 'Шаги',
      subtitle: '15 января',
      inputs: const [
        TraceInput(
          label: 'Шаги за 15 января — com.samsung.health',
          valueText: '8 000',
          kind: TraceSourceKind.healthConnect,
        ),
        TraceInput(
          label: 'Шаги за 15 января — com.google.fit',
          valueText: '6 000',
          kind: TraceSourceKind.healthConnect,
          notUsed: true,
          notUsedReason: 'сумма меньше',
        ),
      ],
      steps: const [
        TraceStep(title: 'Суммируем записи', resultText: '= 8 000'),
      ],
      resultText: '8 000',
      resultUnit: 'шагов',
      dayRows: [
        for (var i = 0; i < dayCount; i++)
          TraceDayRow(dateText: '1$i января', valueText: '8 000'),
      ],
      dayRowsCollapsedByDefault: collapsedDays,
      emaRows: const [
        TraceEmaRow(dateText: '14 января', rawWeight: 84.0, ema: 84.2),
        TraceEmaRow(dateText: '15 января', rawWeight: 84.5, ema: 84.3),
      ],
    );
  }

  Future<void> openSheet(WidgetTester tester, CalcTrace trace) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: cmTheme(Brightness.light),
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showCalcDetailSheet(context, trace),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('чекбокс переключает видимость конкурентов', (tester) async {
    await openSheet(tester, buildTrace());

    // Конкурент скрыт, чекбокс есть.
    expect(find.text('не учтено: сумма меньше'), findsNothing);
    expect(find.textContaining('не попавшие в расчёт'), findsOneWidget);

    await tester.tap(find.textContaining('не попавшие в расчёт'));
    await tester.pumpAndSettle();
    expect(find.text('не учтено: сумма меньше'), findsOneWidget);

    // Обратно скрывается.
    await tester.tap(find.textContaining('не попавшие в расчёт'));
    await tester.pumpAndSettle();
    expect(find.text('не учтено: сумма меньше'), findsNothing);
  });

  testWidgets('таблица свёрнута при collapsedByDefault, кнопка разворачивает',
      (tester) async {
    await openSheet(tester, buildTrace(collapsedDays: true, dayCount: 6));

    // Превью — 3 строки, полной таблицы нет.
    expect(find.text('10 января'), findsOneWidget);
    expect(find.text('14 января'), findsNothing);
    expect(find.text('Показать все дни (6)'), findsOneWidget);

    await tester.ensureVisible(find.text('Показать все дни (6)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать все дни (6)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('14 января'));
    await tester.pumpAndSettle();
    expect(find.text('14 января'), findsOneWidget);
    expect(find.text('Свернуть'), findsOneWidget);
  });

  testWidgets('кнопка «Показать все шаги EMA» разворачивает цепочку',
      (tester) async {
    await openSheet(tester, buildTrace());

    await tester.scrollUntilVisible(
      find.text('Показать все шаги EMA (2)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Показать все шаги EMA (2)'), findsOneWidget);
    await tester.tap(find.text('Показать все шаги EMA (2)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('84.00 → 84.20'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('ШАГИ EMA'), findsOneWidget);
    expect(find.text('84.00 → 84.20'), findsOneWidget);
  });
}
