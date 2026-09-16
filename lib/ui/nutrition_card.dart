import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';
import 'package:cut_metrics/ui/format.dart';
import 'package:cut_metrics/ui/metric_card_state.dart';
import 'package:cut_metrics/ui/source_badge.dart';
import 'package:cut_metrics/ui/source_settings_screen.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';

/// Карточка «Питание» для конкретной даты — 7 состояний (Фаза 7, B.2;
/// дизайн-система §05 «Карточка „Питание“ — Фаза 7»).
///
/// По образцу `MetricCard` Фазы 6, отличия:
/// - значение — ккал за день (+ макросы в ручном «Итоге дня»);
/// - под числом прихода — mono-строка «Расход ≈ 2 400 · Баланс −250»
///   (только когда расход рассчитан — каскад BMR);
/// - форма ручного ввода — 4 поля: ккал (обязательно, шире) + Б/Ж/У, г;
/// - manualConfirmed — «Итог дня: 2 100 ккал · Б 150 · Ж 70 · У 220» +
///   «Изменить / Удалить».
class NutritionCard extends StatefulWidget {
  final DateKey date;
  final DashboardViewModel viewModel;

  const NutritionCard({
    super.key,
    required this.date,
    required this.viewModel,
  });

  @override
  State<NutritionCard> createState() => _NutritionCardState();
}

class _NutritionCardState extends State<NutritionCard> {
  /// Локальный флаг режима ручного ввода (manualEntryActive).
  bool _isManualEntry = false;

  /// Caption «Источник отклонён» сразу после «Не ок».
  bool _refusedCaption = false;

  late TextEditingController _kcalController;
  late TextEditingController _proteinController;
  late TextEditingController _fatController;
  late TextEditingController _carbsController;

  @override
  void initState() {
    super.initState();
    _kcalController = TextEditingController();
    _proteinController = TextEditingController();
    _fatController = TextEditingController();
    _carbsController = TextEditingController();
  }

  @override
  void dispose() {
    _kcalController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        if (vm.isLoading) return _buildLoading();

        final value = vm.nutritionFor(widget.date);

        var baseState = baseStateFromValue(
          _asResolved(value),
          sourceRefused: vm.isSourceRefused(widget.date, MetricType.nutrition),
        );

        // autoConfirmed: решение «доверяем» ИЛИ источник выбран явно (C.4).
        if (baseState == MetricCardState.autoUnconfirmed &&
            vm.isSourceTrusted(MetricType.nutrition, value?.sourcePackage)) {
          baseState = MetricCardState.autoConfirmed;
        }

        if (_isManualEntry) return _buildForm(baseState);

        return switch (baseState) {
          MetricCardState.missing => _buildMissing(),
          MetricCardState.sourceRefused => _buildSourceRefused(),
          MetricCardState.autoUnconfirmed => _buildAutoUnconfirmed(value!),
          MetricCardState.autoConfirmed => _buildAutoConfirmed(value!),
          MetricCardState.manualConfirmed => _buildManualConfirmed(value!),
          _ => _buildLoading(),
        };
      },
    );
  }

  /// Обёртка в [ResolvedValue] для `baseStateFromValue` (механика Фазы 6).
  ResolvedValue<num>? _asResolved(NutritionDay? n) => n == null
      ? null
      : ResolvedValue(
          value: n.calories,
          source: n.source,
          sourcePackage: n.sourcePackage,
        );

  // ─── Оболочка и состояния ────────────────────────────────────────────────────

  Widget _shell({Widget? trailing, required Widget child}) {
    final colors = context.cmColors;
    final d = widget.date.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Питание', style: CMFonts.heading(size: 16, color: colors.ink)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}',
                      style: CMFonts.caption(size: 11, color: colors.noise),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: CMSpacing.sp1),
                      trailing,
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

  Widget _buildLoading() => _shell(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: CMSpacing.sp4),
            child: CircularProgressIndicator(),
          ),
        ),
      );

  Widget _buildMissing() {
    final colors = context.cmColors;
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Нет данных о питании за сегодня. Подключите трекер к Health '
            'Connect или введите итог дня вручную.',
            style: CMFonts.body(size: 14, color: colors.inkMuted),
          ),
          const SizedBox(height: CMSpacing.sp3),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startManualEntry,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Ввести итог'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceRefused() {
    final colors = context.cmColors;
    return _shell(
      trailing: _menu(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Источник отклонён — введите итог дня вручную.',
            style: CMFonts.body(size: 14, color: colors.inkMuted),
          ),
          const SizedBox(height: CMSpacing.sp3),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startManualEntry,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Ввести итог'),
            ),
          ),
        ],
      ),
    );
  }

  /// autoUnconfirmed: значение + бедж + крупные «Ок / Не ок» (B.2).
  Widget _buildAutoUnconfirmed(NutritionDay value) {
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _valueRow(value.calories),
          if (_expenditureLine() != null) ...[
            const SizedBox(height: CMSpacing.sp1),
            _expenditureLine()!,
          ],
          const SizedBox(height: CMSpacing.sp2),
          SourceBadge(
            source: DataSource.external,
            sourcePackage: value.sourcePackage,
          ),
          const SizedBox(height: CMSpacing.sp3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.viewModel.confirmSource(
                    MetricType.nutrition,
                    value.sourcePackage ?? '',
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Ок'),
                ),
              ),
              const SizedBox(width: CMSpacing.sp2),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _onNotOk,
                  icon: const Icon(Icons.block_outlined, size: 18),
                  label: const Text('Не ок'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// autoConfirmed: компакт + меню «⋯» (как Фаза 6).
  Widget _buildAutoConfirmed(NutritionDay value) {
    return _shell(
      trailing: _menu(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _valueRow(value.calories),
          if (_expenditureLine() != null) ...[
            const SizedBox(height: CMSpacing.sp1),
            _expenditureLine()!,
          ],
          const SizedBox(height: CMSpacing.sp2),
          SourceBadge(
            source: DataSource.external,
            sourcePackage: value.sourcePackage,
          ),
        ],
      ),
    );
  }

  /// manualConfirmed: «Итог дня: N ккал · Б N · Ж N · У N» + Изменить/Удалить.
  Widget _buildManualConfirmed(NutritionDay value) {
    final colors = context.cmColors;
    final macros = [
      if (value.protein != null) 'Б ${value.protein!.round()}',
      if (value.fat != null) 'Ж ${value.fat!.round()}',
      if (value.carbs != null) 'У ${value.carbs!.round()}',
    ].join(' · ');
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Итог дня: ${formatThousands(value.calories)} ккал'
            '${macros.isEmpty ? '' : ' · $macros'}',
            style: CMFonts.metric(size: 20, color: colors.ink),
          ),
          const SizedBox(height: CMSpacing.sp3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SourceBadge(source: DataSource.manual),
              Row(
                children: [
                  TextButton(
                      onPressed: _startManualEntry,
                      child: const Text('Изменить')),
                  TextButton(
                    onPressed: _onDelete,
                    style: TextButton.styleFrom(foregroundColor: colors.alert),
                    child: const Text('Удалить'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Большое значение прихода «2 150 ккал сегодня».
  Widget _valueRow(double calories) {
    final colors = context.cmColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          formatThousands(calories),
          style: CMFonts.metric(size: 32, color: colors.ink),
        ),
        const SizedBox(width: CMSpacing.sp1),
        Text('ккал сегодня',
            style: CMFonts.caption(size: 12, color: colors.noise)),
      ],
    );
  }

  /// «Расход ≈ 2 400 · Баланс −250» — только если расход рассчитан.
  Widget? _expenditureLine() {
    final vm = widget.viewModel;
    final value = vm.nutritionFor(widget.date);
    final exp = vm.expenditureFor(widget.date);
    if (value == null || exp == null) return null;
    final colors = context.cmColors;
    return Text(
      'Расход ≈ ${formatThousands(exp.total)} · '
      'Баланс ${formatSignedKcal(value.calories - exp.total)}',
      style: CMFonts.caption(size: 11, color: colors.inkMuted),
    );
  }

  // ─── Форма «Итог дня» (manualEntryActive) ────────────────────────────────────

  /// Форма: ккал (обязательно, шире) + Б/Ж/У в граммах (опционально).
  Widget _buildForm(MetricCardState baseState) {
    final colors = context.cmColors;
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_refusedCaption) ...[
            Text(
              'Источник отклонён — введите итог дня вручную.',
              style: CMFonts.body(size: 13, color: colors.inkMuted),
            ),
            const SizedBox(height: CMSpacing.sp2),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _kcalController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Ккал *',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: CMSpacing.sp2),
              Expanded(
                child: TextField(
                  controller: _proteinController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Б, г',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CMSpacing.sp2),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fatController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Ж, г',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: CMSpacing.sp2),
              Expanded(
                child: TextField(
                  controller: _carbsController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'У, г',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CMSpacing.sp3),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _submit,
                  child: const Text('Сохранить'),
                ),
              ),
              const SizedBox(width: CMSpacing.sp2),
              TextButton(
                onPressed: _cancelManualMode,
                child: const Text('Отмена'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Действия ────────────────────────────────────────────────────────────────

  /// Меню «⋯»: доверять / отклонить / настроить источники (механика Фазы 6).
  Widget _menu() {
    final vm = widget.viewModel;
    final value = vm.nutritionFor(widget.date);
    final package = value?.sourcePackage;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'Действия',
      onSelected: (action) {
        switch (action) {
          case 'trust':
            if (package != null) {
              vm.confirmSource(MetricType.nutrition, package);
            }
          case 'refuse':
            if (package != null) {
              vm.refuseSource(MetricType.nutrition, package);
              setState(() {
                _isManualEntry = true;
                _refusedCaption = true;
              });
            }
          case 'sources':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SourceSettingsScreen(metric: MetricType.nutrition),
              ),
            );
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'trust', child: Text('Доверять источнику')),
        PopupMenuItem(value: 'refuse', child: Text('Отклонить источник')),
        PopupMenuItem(value: 'sources', child: Text('Настроить источники')),
      ],
    );
  }

  /// «Не ок» — постоянный отказ источника + сразу форма ввода (B.3 Фазы 6).
  void _onNotOk() {
    final vm = widget.viewModel;
    final package = vm.nutritionFor(widget.date)?.sourcePackage;
    if (package != null) {
      vm.refuseSource(MetricType.nutrition, package);
    }
    setState(() {
      _isManualEntry = true;
      _refusedCaption = true;
    });
  }

  /// Вход в форму: префилл текущим «Итогом дня» при правке.
  void _startManualEntry() {
    final current = widget.viewModel.nutritionFor(widget.date);
    if (current != null && current.source == DataSource.manual) {
      _kcalController.text =
          current.calories == current.calories.roundToDouble()
              ? current.calories.round().toString()
              : current.calories.toStringAsFixed(1);
      if (current.protein != null) _proteinController.text = current.protein!.round().toString();
      if (current.fat != null) _fatController.text = current.fat!.round().toString();
      if (current.carbs != null) _carbsController.text = current.carbs!.round().toString();
    }
    setState(() => _isManualEntry = true);
  }

  /// Сохранение «Итога дня»: ккал обязательно (bool-возврат + снекбар).
  Future<void> _submit() async {
    final kcal = double.tryParse(_kcalController.text.replaceAll(',', '.'));
    if (kcal == null || kcal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите калорийность итога дня'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    double? parseOr(String text) {
      final t = text.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t.replaceAll(',', '.'));
    }

    final ok = await widget.viewModel.submitManualNutrition(
      widget.date,
      calories: kcal,
      protein: parseOr(_proteinController.text),
      fat: parseOr(_fatController.text),
      carbs: parseOr(_carbsController.text),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить итог дня'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (ok) {
      setState(() {
        _isManualEntry = false;
        _refusedCaption = false;
        _kcalController.clear();
        _proteinController.clear();
        _fatController.clear();
        _carbsController.clear();
      });
    }
  }

  /// Отмена ввода — возврат в предыдущее состояние.
  void _cancelManualMode() {
    setState(() {
      _isManualEntry = false;
      _refusedCaption = false;
      _kcalController.clear();
      _proteinController.clear();
      _fatController.clear();
      _carbsController.clear();
    });
  }

  /// «Удалить» из manualConfirmed — откат на внешние данные/missing.
  Future<void> _onDelete() async {
    final ok = await widget.viewModel.cancelManualNutrition(widget.date);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось удалить итог дня'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

