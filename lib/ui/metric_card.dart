import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/ui/metric_card_state.dart';
import 'package:cut_metrics/ui/source_badge.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';

/// Карточка метрики для конкретной даты — 5 состояний (Фаза 3, секция 3–4).
///
/// Состояния:
/// - `loading` → скелетон/спиннер
/// - `missing` → "нет данных" + кнопка "ввести"
/// - `autoUnconfirmed` → значение + кнопки "ок" / "не ок"
/// - `manualEntryActive` → TextField + submit/cancel
/// - `manualConfirmed` → значение + кнопка "отменить"
///
/// `manualEntryActive` — локальный UI-флаг (StatefulWidget), не из ViewModel.
/// При перезагрузке карточка снова показывает `autoUnconfirmed` (спека, секция 5).
///
/// Блокировка при `missing` — только эта карточка, не весь экран.
class MetricCard extends StatefulWidget {
  final DateKey date;
  final MetricType type;
  final DashboardViewModel viewModel;

  const MetricCard({
    super.key,
    required this.date,
    required this.type,
    required this.viewModel,
  });

  @override
  State<MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<MetricCard> {
  /// Локальный флаг режима ручного ввода (manualEntryActive).
  bool _isManualEntry = false;

  /// Контроллер для поля ввода.
  late TextEditingController _controller;

  // NOTE: `manualEntryActive` — локальный флаг. При отмене ввода карточка
  // возвращается в состояние, вычисляемое из данных через baseStateFromValue.
  // Отдельное хранение _previousState не требуется — оно выводится из кеша.

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => widget.type == MetricType.weight ? 'Вес' : 'Шаги';
  String get _unit => widget.type == MetricType.weight ? 'кг' : 'шагов';

  @override
  Widget build(BuildContext context) {
    // Подписка на изменения ViewModel через ListenableBuilder.
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        if (widget.viewModel.isLoading) {
          return _buildLoading();
        }

        final value = widget.viewModel.getResolvedValue(widget.date, widget.type);
        final baseState = baseStateFromValue(value);

        // Текущее состояние: manualEntryActive — локальный флаг, остальное из данных.
        final state = _isManualEntry ? MetricCardState.manualEntryActive : baseState;

        return switch (state) {
          MetricCardState.loading => _buildLoading(),
          MetricCardState.missing => _buildMissing(),
          MetricCardState.autoUnconfirmed => _buildAutoUnconfirmed(value!),
          MetricCardState.manualEntryActive => _buildManualEntry(),
          MetricCardState.manualConfirmed => _buildManualConfirmed(value!),
        };
      },
    );
  }

  // ─── Состояния карточки ─────────────────────────────────────────────────────

  Widget _buildLoading() {
    return _CardShell(
      title: _title,
      date: widget.date,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildMissing() {
    return _CardShell(
      title: _title,
      date: widget.date,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Нет данных',
            style: CMFonts.body(size: 14, color: CMColors.noise),
          ),
          const SizedBox(height: CMSpacing.sp2),
          ElevatedButton.icon(
            onPressed: _enterManualMode,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Ввести'),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoUnconfirmed(ResolvedValue<num> value) {
    return _CardShell(
      title: _title,
      date: widget.date,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueDisplay(value: value.value, unit: _unit),
          const SizedBox(height: CMSpacing.sp2),
          // Бедж источника: Фаза 5, часть B, таблица B.6.
          const SourceBadge(source: DataSource.external),
          const SizedBox(height: CMSpacing.sp3),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _confirmOk,
                icon: const Icon(Icons.check, size: 16, color: CMColors.steady),
                label: const Text('Ок'),
              ),
              const SizedBox(width: CMSpacing.sp2),
              OutlinedButton.icon(
                onPressed: _enterManualMode,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Не ок'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntry() {
    return _CardShell(
      title: _title,
      date: widget.date,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: widget.type == MetricType.weight
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.number,
                  decoration: InputDecoration(
                    hintText: widget.type == MetricType.weight ? 'Вес, кг' : 'Шаги',
                    suffixText: _unit,
                  ),
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: CMSpacing.sp2),
              IconButton(
                onPressed: _submit,
                icon: const Icon(Icons.check_circle, color: CMColors.signal),
                tooltip: 'Сохранить',
              ),
              IconButton(
                onPressed: _cancelManualMode,
                icon: const Icon(Icons.close, color: CMColors.noise),
                tooltip: 'Отмена',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualConfirmed(ResolvedValue<num> value) {
    return _CardShell(
      title: _title,
      date: widget.date,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueDisplay(value: value.value, unit: _unit),
          const SizedBox(height: CMSpacing.sp2),
          // Бедж источника: Фаза 5, часть B, таблица B.6.
          const SourceBadge(source: DataSource.manual),
          const SizedBox(height: CMSpacing.sp3),
          TextButton.icon(
            onPressed: _cancelValue,
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Отменить'),
          ),
        ],
      ),
    );
  }

  // ─── Действия ───────────────────────────────────────────────────────────────

  /// "Ок" — БЕЗ побочных эффектов (Фаза 3, секция 5).
  ///
  /// Не вызывает writeManualRecord/deleteManualRecord — чисто визуальная реакция.
  void _confirmOk() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$_title подтверждён'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// "Не ок" / "ввести" — переход в manualEntryActive.
  void _enterManualMode() {
    setState(() {
      _isManualEntry = true;

      // Предзаполняем поле текущим значением, если оно есть.
      final value = widget.viewModel.getResolvedValue(widget.date, widget.type);
      if (value != null) {
        _controller.text = value.value.toString();
      }
    });
  }

  /// Submit — вызывает submitManualValue → состояние manualConfirmed.
  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final value = widget.type == MetricType.weight
        ? double.tryParse(text.replaceAll(',', '.'))
        : int.tryParse(text);

    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Некорректное значение'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isManualEntry = false);
    widget.viewModel.submitManualValue(widget.date, widget.type, value);
  }

  /// Отмена ввода — возврат в предыдущее состояние (missing | autoUnconfirmed).
  void _cancelManualMode() {
    setState(() {
      _isManualEntry = false;
      _controller.clear();
    });
  }

  /// "Отменить" из manualConfirmed — вызывает cancelManualValue → откат на Tier 2.
  void _cancelValue() {
    widget.viewModel.cancelManualValue(widget.date, widget.type);
  }
}

// ─── Вспомогательные виджеты ───────────────────────────────────────────────────

/// Оболочка карточки с заголовком и датой.
class _CardShell extends StatelessWidget {
  final String title;
  final DateKey date;
  final Widget child;

  const _CardShell({
    required this.title,
    required this.date,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final d = date.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: CMFonts.heading(size: 16)),
                Text(
                  '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}',
                  style: CMFonts.caption(size: 11),
                ),
              ],
            ),
            const SizedBox(height: CMSpacing.sp3),
            child,
          ],
        ),
      ),
    );
  }
}

/// Отображение значения метрики.
///
/// Бедж источника выведен из этого виджета в Фазе 5 — состоянием карточки
/// управляет [SourceBadge] (таблица B.6), рядом со значением только число и юнит.
class _ValueDisplay extends StatelessWidget {
  final num value;
  final String unit;

  const _ValueDisplay({
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final formatted =
        value is int ? value.toString() : (value as double).toStringAsFixed(1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          formatted,
          style: CMFonts.metric(size: 32, color: CMColors.ink),
        ),
        const SizedBox(width: CMSpacing.sp1),
        Text(unit, style: CMFonts.caption(size: 12)),
      ],
    );
  }
}