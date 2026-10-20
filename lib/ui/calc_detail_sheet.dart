import 'package:cut_metrics/domain/calc_trace.dart';
import 'package:cut_metrics/services/source_names.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:flutter/material.dart';

/// Нижний лист «Как рассчитано» (CalcDetail, §6 ТЗ).
///
/// Показывает трассу [CalcTrace]: секции «Исходные данные» / «Расчёт» /
/// «Итог», конкуренты за чекбоксом «Показать данные, не попавшие в расчёт»,
/// таблица дней среднесуточных (свёрнута при 90 днях), цепочка EMA за своей
/// кнопкой. Все раскрытия — одна анимация `AnimatedSize`
/// (220 мс, `Curves.fastOutSlowIn`, решение пользователя 2026-09-23).
///
/// Цвета — только роли темы (`context.cmColors`), новых hex нет; имена
/// источников — словарь `source_names.dart` с fallback.
void showCalcDetailSheet(BuildContext context, CalcTrace trace) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Высота по контенту, максимум ~0.8 экрана (§6 ТЗ).
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    backgroundColor: context.cmColors.surface0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(CMRadius.xl)),
    ),
    builder: (_) => _CalcDetailSheet(trace: trace),
  );
}

/// Иконка-аффорданс «ⓘ» для точек входа «Как рассчитано» (§6 ТЗ): у подписи
/// большого числа, у среднесуточных Тренда, у темпа/рекомендации Саммари.
class CalcInfoIcon extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const CalcInfoIcon({super.key, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CMRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.info_outline, size: 16, color: colors.noise),
        ),
      ),
    );
  }
}

class _CalcDetailSheet extends StatefulWidget {
  final CalcTrace trace;

  const _CalcDetailSheet({required this.trace});

  @override
  State<_CalcDetailSheet> createState() => _CalcDetailSheetState();
}

class _CalcDetailSheetState extends State<_CalcDetailSheet> {
  static const _revealAnimation = Duration(milliseconds: 220);

  /// Чекбокс «Показать данные, не попавшие в расчёт».
  bool _showNotUsed = false;

  /// Раскрытие таблицы дней (свёрнута при `dayRowsCollapsedByDefault`).
  bool _daysExpanded = false;

  /// Раскрытие цепочки EMA.
  bool _emaExpanded = false;

  @override
  void initState() {
    super.initState();
    // 7/30 дней — таблица сразу раскрыта; 90 — до кнопки (решение п. 5).
    _daysExpanded = !widget.trace.dayRowsCollapsedByDefault;
  }

  @override
  Widget build(BuildContext context) {
    final trace = widget.trace;
    final colors = context.cmColors;
    final unused = trace.inputs.where((i) => i.notUsed).toList();
    final used = trace.inputs.where((i) => !i.notUsed).toList();

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
            CMSpacing.sp6, CMSpacing.sp4, CMSpacing.sp6, CMSpacing.sp6),
        children: [
          // ── Ручка + заголовок ──
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: CMSpacing.sp4),
              decoration: BoxDecoration(
                color: colors.outlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trace.title,
                        style: CMFonts.heading(size: 20, color: colors.ink)),
                    if (trace.subtitle != null)
                      Text(trace.subtitle!,
                          style:
                              CMFonts.caption(size: 12, color: colors.noise)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: colors.inkMuted, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Закрыть',
              ),
            ],
          ),
          const SizedBox(height: CMSpacing.sp4),

          // ── Исходные данные ──
          if (used.isNotEmpty || unused.isNotEmpty) ...[
            const _SectionTitle('Исходные данные'),
            for (final input in used) _InputRow(input: input),
            if (unused.isNotEmpty)
              AnimatedSize(
                duration: _revealAnimation,
                curve: Curves.fastOutSlowIn,
                alignment: Alignment.topCenter,
                child: _showNotUsed
                    ? Column(
                        children: [
                          for (final input in unused) _InputRow(input: input),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            if (unused.isNotEmpty)
              CheckboxListTile(
                value: _showNotUsed,
                onChanged: (v) => setState(() => _showNotUsed = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Показать данные, не попавшие в расчёт (${unused.length})',
                  style: CMFonts.body(size: 13, color: colors.inkMuted),
                ),
              ),
            const SizedBox(height: CMSpacing.sp4),
          ],

          // ── Расчёт ──
          if (trace.steps.isNotEmpty) ...[
            const _SectionTitle('Расчёт'),
            for (final step in trace.steps) _StepRow(step: step),
            const SizedBox(height: CMSpacing.sp4),
          ],

          // ── Таблица дней ──
          if (trace.dayRows != null && trace.dayRows!.isNotEmpty) ...[
            _DaysTable(
              rows: trace.dayRows!,
              expanded: _daysExpanded,
              onToggle: () => setState(() => _daysExpanded = !_daysExpanded),
            ),
            const SizedBox(height: CMSpacing.sp4),
          ],

          // ── Цепочка EMA ──
          if (trace.emaRows != null && trace.emaRows!.isNotEmpty) ...[
            _EmaChain(
              rows: trace.emaRows!,
              expanded: _emaExpanded,
              onToggle: () => setState(() => _emaExpanded = !_emaExpanded),
            ),
            const SizedBox(height: CMSpacing.sp4),
          ],

          // ── Итог ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(CMSpacing.sp4),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(CMRadius.md),
              border: Border.all(color: colors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ИТОГ',
                    style: CMFonts.caption(size: 11, color: colors.noise)),
                const SizedBox(height: CMSpacing.sp2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        trace.resultText,
                        style: CMFonts.metric(size: 30, color: colors.signal),
                      ),
                    ),
                    if (trace.resultUnit != null) ...[
                      const SizedBox(width: CMSpacing.sp2),
                      Flexible(
                        child: Text(trace.resultUnit!,
                            style: CMFonts.caption(
                                size: 12, color: colors.inkMuted)),
                      ),
                    ],
                  ],
                ),
                if (trace.resultNote != null) ...[
                  const SizedBox(height: CMSpacing.sp2),
                  Text(trace.resultNote!,
                      style: CMFonts.body(size: 13, color: colors.inkMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: CMSpacing.sp2),
      child: Text(
        text.toUpperCase(),
        style: CMFonts.caption(size: 11, color: colors.noise),
      ),
    );
  }
}

/// Одна строка входа: подпись · значение · бейдж источника · примечание.
class _InputRow extends StatelessWidget {
  final TraceInput input;

  const _InputRow({required this.input});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Opacity(
      // Конкуренты (за чекбоксом) — приглушены.
      opacity: input.notUsed ? 0.7 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CMSpacing.sp1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(input.label,
                      style: CMFonts.body(size: 13, color: colors.ink)),
                ),
                const SizedBox(width: CMSpacing.sp2),
                Text(input.valueText,
                    style: CMFonts.metric(size: 14, color: colors.inkMuted)),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: CMSpacing.sp2,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _KindBadge(kind: input.kind, package: input.sourceName),
                if (input.recordsText != null)
                  Text(input.recordsText!,
                      style: CMFonts.caption(size: 11, color: colors.noise)),
                if (input.note != null)
                  Text(input.note!,
                      style: CMFonts.caption(size: 11, color: colors.noise)),
                if (input.notUsed && input.notUsedReason != null)
                  Text('не учтено: ${input.notUsedReason}',
                      style: CMFonts.caption(size: 11, color: colors.alert)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// Бейдж типа источника числа (язык макетов CalcDetail):
/// HEALTH CONNECT / РУЧНОЙ ВВОД / НАСТРОЙКИ / ФОРМУЛА / РАСЧЁТ.
class _KindBadge extends StatelessWidget {
  final TraceSourceKind kind;
  final String? package;

  const _KindBadge({required this.kind, this.package});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    final (label, isManual) = switch (kind) {
      TraceSourceKind.healthConnect => (
          package == null ? 'HEALTH CONNECT' : displaySourceName(package!),
          false
        ),
      TraceSourceKind.manual => ('РУЧНОЙ ВВОД', true),
      TraceSourceKind.settings => ('НАСТРОЙКИ', false),
      TraceSourceKind.formula => ('ФОРМУЛА', false),
      TraceSourceKind.computed => ('РАСЧЁТ', false),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: CMSpacing.sp2, vertical: 2),
      decoration: ShapeDecoration(
        color: isManual ? colors.signalTint : colors.surface2,
        shape: StadiumBorder(side: BorderSide(color: colors.outline)),
      ),
      child: Text(
        label,
        style: CMFonts.label(
            size: 10, color: isManual ? colors.ink : colors.inkMuted),
      ),
    );
  }
}

/// Шаг расчёта: заголовок · формула (моно) · результат · примечание.
class _StepRow extends StatelessWidget {
  final TraceStep step;

  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: CMSpacing.sp3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: colors.signal, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: CMSpacing.sp2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: CMFonts.body(size: 13, color: colors.ink)),
                if (step.formulaText != null) ...[
                  const SizedBox(height: 2),
                  Text(step.formulaText!,
                      style: CMFonts.caption(size: 11, color: colors.inkMuted)),
                ],
                if (step.resultText != null) ...[
                  const SizedBox(height: 2),
                  Text(step.resultText!,
                      style: CMFonts.metric(size: 14, color: colors.ink)),
                ],
                if (step.note != null) ...[
                  const SizedBox(height: 2),
                  Text(step.note!,
                      style: CMFonts.caption(size: 11, color: colors.noise)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка-раскрытие (общая для таблицы дней и цепочки EMA).
class _RevealButton extends StatelessWidget {
  final bool expanded;
  final String collapsedText;
  final String expandedText;
  final VoidCallback onToggle;

  const _RevealButton({
    required this.expanded,
    required this.collapsedText,
    required this.expandedText,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return InkWell(
      borderRadius: BorderRadius.circular(CMRadius.sm),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CMSpacing.sp2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? expandedText : collapsedText,
              style: CMFonts.label(size: 12, color: colors.signal),
            ),
            const SizedBox(width: CMSpacing.sp1),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: colors.signal,
            ),
          ],
        ),
      ),
    );
  }
}


/// Таблица «дата · значение (· значение · значение) · источник»: 1 колонка
/// значения для среднесуточных, 3 — для энергобаланса недели (приход ·
/// расход · баланс). Свёрнутая — кнопка «Показать все дни (N)».
class _DaysTable extends StatelessWidget {
  final List<TraceDayRow> rows;
  final bool expanded;
  final VoidCallback onToggle;

  const _DaysTable(
      {required this.rows, required this.expanded, required this.onToggle});

  static const _collapsedPreview = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    final shown = expanded ? rows : rows.take(_collapsedPreview).toList();
    final multi = rows.any((r) => r.value2Text != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ДНИ, ВОШЕДШИЕ В РАСЧЁТ',
            style: CMFonts.caption(size: 11, color: colors.noise)),
        const SizedBox(height: CMSpacing.sp2),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.fastOutSlowIn,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (final r in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(r.dateText,
                            style: CMFonts.caption(
                                size: 11, color: colors.inkMuted)),
                      ),
                      Expanded(
                        child: Text(
                          multi
                              ? '${r.valueText} · ${r.value2Text ?? ''} · ${r.value3Text ?? ''}'
                              : r.valueText,
                          style: CMFonts.metric(size: 13, color: colors.ink),
                        ),
                      ),
                      if (!multi && r.sourceName != null)
                        Flexible(
                          child: Text(
                            displaySourceName(r.sourceName!),
                            overflow: TextOverflow.ellipsis,
                            style:
                                CMFonts.caption(size: 11, color: colors.noise),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (rows.length > _collapsedPreview)
          _RevealButton(
            expanded: expanded,
            collapsedText: 'Показать все дни (${rows.length})',
            expandedText: 'Свернуть',
            onToggle: onToggle,
          ),
      ],
    );
  }
}


/// Цепочка EMA «дата · сырой вес → EMA»: скрыта за кнопкой «Показать все
/// шаги EMA (N)»; строки после разрыва серии помечены.
class _EmaChain extends StatelessWidget {
  final List<TraceEmaRow> rows;
  final bool expanded;
  final VoidCallback onToggle;

  const _EmaChain(
      {required this.rows, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.fastOutSlowIn,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ШАГИ EMA',
                        style:
                            CMFonts.caption(size: 11, color: colors.noise)),
                    const SizedBox(height: CMSpacing.sp2),
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 92,
                                  child: Text(r.dateText,
                                      style: CMFonts.caption(
                                          size: 11, color: colors.inkMuted)),
                                ),
                                Expanded(
                                  child: Text(
                                    '${r.rawWeight.toStringAsFixed(2)} → ${r.ema.toStringAsFixed(2)}',
                                    style: CMFonts.metric(
                                        size: 13,
                                        color: r.seriesRestart
                                            ? colors.alert
                                            : colors.ink),
                                  ),
                                ),
                              ],
                            ),
                            if (r.seriesRestart)
                              Text('Разрыв — серия стартует заново',
                                  style: CMFonts.caption(
                                      size: 11, color: colors.alert)),
                          ],
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
        _RevealButton(
          expanded: expanded,
          collapsedText: 'Показать все шаги EMA (${rows.length})',
          expandedText: 'Свернуть шаги EMA',
          onToggle: onToggle,
        ),
      ],
    );
  }
}

