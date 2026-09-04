import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/services/source_names.dart';
import 'package:cut_metrics/ui/metric_card_state.dart';
import 'package:cut_metrics/ui/source_badge.dart';
import 'package:cut_metrics/ui/source_settings_screen.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';

/// Карточка метрики для конкретной даты — 7 состояний (Фаза 3, секция 3–4;
/// Фаза 6, B.4 — `autoConfirmed` и `sourceRefused`).
///
/// Состояния:
/// - `loading` → скелетон/спиннер
/// - `missing` → «нет данных» + кнопка «Ввести»
/// - `autoUnconfirmed` → значение + бедж с именем приложения + «Ок» / «Не ок»
/// - `autoConfirmed` → компакт: значение + «Подтверждено · Google Fit» + «⋯»
/// - `sourceRefused` → «Источник отклонён · введите значение» + ввод + «⋯»
/// - `manualEntryActive` → TextField + submit/cancel
/// - `manualConfirmed` → значение + «Ручной ввод» + «Отменить»
///
/// Фаза 6: «Ок» пишет решение (не данные) — карточка становится тихой;
/// «Не ок» = постоянный отказ источника + сразу ручной ввод + снекбар;
/// меню «⋯» (в autoConfirmed/sourceRefused): доверять / отклонить /
/// настроить источники.
///
/// `manualEntryActive` — локальный UI-флаг (StatefulWidget), не из ViewModel.
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

  /// Показывать caption «Источник отклонён» в режиме ввода — сразу после
  /// «Не ок» (пока резолюция ещё не перестроилась в sourceRefused).
  bool _refusedCaption = false;

  /// Контроллер для поля ввода.
  late TextEditingController _controller;

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

        final vm = widget.viewModel;
        final value = vm.getResolvedValue(widget.date, widget.type);

        // Базовое состояние из данных (Фаза 6: sourceRefused vs missing).
        var baseState = baseStateFromValue(
          value,
          sourceRefused: vm.isSourceRefused(widget.date, widget.type),
        );

        // autoConfirmed: решение «доверяем» ИЛИ источник выбран явно (C.4).
        if (baseState == MetricCardState.autoUnconfirmed &&
            vm.isSourceTrusted(widget.type, value!.sourcePackage)) {
          baseState = MetricCardState.autoConfirmed;
        }

        final state = _isManualEntry ? MetricCardState.manualEntryActive : baseState;

        return switch (state) {
          MetricCardState.loading => _buildLoading(),
          MetricCardState.missing => _buildMissing(),
          MetricCardState.autoUnconfirmed => _buildAutoUnconfirmed(value!),
          MetricCardState.autoConfirmed => _buildAutoConfirmed(value!),
          MetricCardState.sourceRefused => _buildSourceRefused(),
          MetricCardState.manualEntryActive => _buildManualEntry(
            caption: _refusedCaption || widget.viewModel.isSourceRefused(
              widget.date,
              widget.type,
            ),
          ),
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
    final colors = context.cmColors;
    return _CardShell(
      title: _title,
      date: widget.date,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Нет данных',
            style: CMFonts.body(size: 14, color: colors.noise),
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
    final colors = context.cmColors;
    return _CardShell(
      title: _title,
      date: widget.date,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueDisplay(value: value.value, unit: _unit),
          const SizedBox(height: CMSpacing.sp2),
          // Бедж источника с именем приложения (Фаза 6, C.3).
          SourceBadge(source: DataSource.external, sourcePackage: value.sourcePackage),
          const SizedBox(height: CMSpacing.sp3),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _confirmOk,
                icon: Icon(Icons.check, size: 16, color: colors.steady),
                label: const Text('Ок'),
              ),
              const SizedBox(width: CMSpacing.sp2),
              OutlinedButton.icon(
                onPressed: _refuseAndEnter,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Не ок'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Компактная тихая карточка (Фаза 6, задание №1 §7): значение + строка
  /// «Подтверждено · Google Fit» (steady-точка, caption) + меню «⋯».
  Widget _buildAutoConfirmed(ResolvedValue<num> value) {
    final colors = context.cmColors;
    return _CardShell(
      title: _title,
      date: widget.date,
      trailing: _buildMenuButton(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueDisplay(value: value.value, unit: _unit),
          const SizedBox(height: CMSpacing.sp2),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: colors.steady, shape: BoxShape.circle),
              ),
              const SizedBox(width: CMSpacing.sp2),
              Expanded(
                child: Text(
                  'Подтверждено · ${displaySourceName(value.sourcePackage ?? '')}',
                  style: CMFonts.caption(size: 11, color: colors.inkMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Все доступные источники отклонены (Фаза 6): режим ручного ввода по
  /// умолчанию + caption «Источник отклонён · введите значение» + меню «⋯».
  Widget _buildSourceRefused() {
    return _buildManualEntry(caption: true, refuseMode: true);
  }

  /// Поле ручного ввода. [caption] — строка «Источник отклонён · введите
  /// значение» (sourceRefused или сразу после «Не ок»). [refuseMode] —
  /// в sourceRefused кнопка «✕» очищает поле (возвращаться не к чему),
  /// в обычном режиме — отменяет ввод.
  Widget _buildManualEntry({bool caption = false, bool refuseMode = false}) {
    final colors = context.cmColors;
    return _CardShell(
      title: _title,
      date: widget.date,
      trailing: caption ? _buildMenuButton() : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption) ...[
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: colors.alert, shape: BoxShape.circle),
                ),
                const SizedBox(width: CMSpacing.sp2),
                Expanded(
                  child: Text(
                    'Источник отклонён · введите значение',
                    style: CMFonts.caption(size: 11, color: colors.inkMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CMSpacing.sp2),
          ],
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
                icon: Icon(Icons.check_circle, color: colors.signal),
                tooltip: 'Сохранить',
              ),
              IconButton(
                onPressed: () {
                  if (refuseMode) {
                    _controller.clear();
                  } else {
                    _cancelManualMode();
                  }
                },
                icon: Icon(Icons.close, color: colors.noise),
                tooltip: refuseMode ? 'Очистить' : 'Отмена',
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

  /// «Ок» — пишет решение «доверяем» для источника (Фаза 6, B.2).
  ///
  /// Данные НЕ пишет — только персистентное решение на пару
  /// (метрика + источник); карточка становится тихой (autoConfirmed).
  /// Мгновенный снекбар остаётся (Фаза 3, A4).
  void _confirmOk() {
    final value = widget.viewModel.getResolvedValue(widget.date, widget.type);
    final package = value?.sourcePackage;
    if (package != null) {
      widget.viewModel.confirmSource(widget.type, package);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$_title подтверждён'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// «Не ок» — постоянный отказ источника (Фаза 6, B.3): снекбар
  /// «Данные <имя> больше не используются — изменить можно в Настройках»
  /// и сразу ручной ввод (визуально manualEntryActive с caption'ом
  /// sourceRefused).
  void _refuseAndEnter() {
    final value = widget.viewModel.getResolvedValue(widget.date, widget.type);
    final package = value?.sourcePackage;
    if (package != null) {
      widget.viewModel.refuseSource(widget.type, package);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Данные ${displaySourceName(package)} больше не используются — '
            'изменить можно в Настройках',
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    setState(() {
      _isManualEntry = true;
      _refusedCaption = true;
      _prefill();
    });
  }

  /// Меню «⋯» (autoConfirmed / sourceRefused, задание №1 §7):
  /// доверять / отклонить источник / настроить источники.
  Widget _buildMenuButton() {
    final value = widget.viewModel.getResolvedValue(widget.date, widget.type);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Действия с источником',
      onSelected: (action) {
        final package = value?.sourcePackage;
        switch (action) {
          case 'trust':
            if (package != null) widget.viewModel.confirmSource(widget.type, package);
          case 'refuse':
            if (package != null) {
              widget.viewModel.refuseSource(widget.type, package);
              setState(() {
                _isManualEntry = true;
                _refusedCaption = true;
                _prefill();
              });
            }
          case 'settings':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SourceSettingsScreen(metric: widget.type),
              ),
            );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'trust', child: Text('Доверять этому источнику')),
        const PopupMenuItem(
          value: 'refuse',
          child: Text('Отклонить источник (вводить вручную)'),
        ),
        const PopupMenuItem(value: 'settings', child: Text('Настроить источники…')),
      ],
    );
  }

  /// «Ввести» — переход в manualEntryActive.
  void _enterManualMode() {
    setState(() {
      _isManualEntry = true;
      _refusedCaption = false;
      _prefill();
    });
  }

  /// Предзаполняет поле текущим значением, если оно есть.
  void _prefill() {
    final value = widget.viewModel.getResolvedValue(widget.date, widget.type);
    if (value != null) {
      _controller.text = value.value.toString();
    }
  }

  /// Submit — вызывает submitManualValue → состояние manualConfirmed.
  ///
  /// A1.3: при неудачной записи карточка показывает снекбар «Не удалось
  /// сохранить» (ошибка уже в `vm.error` и DebugLog).
  Future<void> _submit() async {
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
    final ok = await widget.viewModel.submitManualValue(
      widget.date,
      widget.type,
      value,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Отмена ввода — возврат в предыдущее состояние (missing | autoUnconfirmed).
  void _cancelManualMode() {
    setState(() {
      _isManualEntry = false;
      _refusedCaption = false;
      _controller.clear();
    });
  }

  /// "Отменить" из manualConfirmed — вызывает cancelManualValue → откат на Tier 2.
  void _cancelValue() {
    widget.viewModel.cancelManualValue(widget.date, widget.type);
  }
}

// ─── Вспомогательные виджеты ───────────────────────────────────────────────────

/// Оболочка карточки с заголовком и датой. [trailing] — «⋯» для тихих
/// состояний Фазы 6 (autoConfirmed / sourceRefused).
class _CardShell extends StatelessWidget {
  final String title;
  final DateKey date;
  final Widget? trailing;
  final Widget child;

  const _CardShell({
    required this.title,
    required this.date,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
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
                Text(title, style: CMFonts.heading(size: 16, color: colors.ink)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}',
                      style: CMFonts.caption(size: 11, color: colors.noise),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: CMSpacing.sp1),
                      trailing!,
                    ],
                  ],
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
    final colors = context.cmColors;
    final formatted =
        value is int ? value.toString() : (value as double).toStringAsFixed(1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          formatted,
          style: CMFonts.metric(size: 32, color: colors.ink),
        ),
        const SizedBox(width: CMSpacing.sp1),
        Text(unit, style: CMFonts.caption(size: 12, color: colors.noise)),
      ],
    );
  }
}