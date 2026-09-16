import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/ui/format.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Блок «Профиль расхода» (Фаза 7, B.4 / макет «Настройки»): пол-сегмент,
/// год рождения, рост (с HC-префиллом) — данные для формулы Mifflin-St Jeor.
///
/// Применение мгновенное, без «Сохранить» (паттерн остальных настроек).
/// Рост: поле показывает ручное значение или HC-префилл; очистка поля
/// возвращает HC-префилл (`energy_height_cm` удаляется).
class EnergyProfileBlock extends StatefulWidget {
  const EnergyProfileBlock({super.key});

  @override
  State<EnergyProfileBlock> createState() => _EnergyProfileBlockState();
}

class _EnergyProfileBlockState extends State<EnergyProfileBlock> {
  late TextEditingController _birthYearController;
  late TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    final vm = context.read<DashboardViewModel>();
    _birthYearController = TextEditingController(
      text: vm.energyProfile.birthYear?.toString() ?? '',
    );
    _heightController = TextEditingController(
      text: vm.effectiveHeightCm == null
          ? ''
          : vm.effectiveHeightCm!.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _birthYearController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _saveProfile(ExpenditureProfile Function(ExpenditureProfile) change) {
    context.read<DashboardViewModel>().setEnergyProfile(
          change(context.read<DashboardViewModel>().energyProfile),
        );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final colors = context.cmColors;
    final profile = vm.energyProfile;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Профиль расхода',
                style: CMFonts.heading(size: 16, color: colors.ink)),
            const SizedBox(height: CMSpacing.sp3),
            SegmentedButton<EnergySex>(
              segments: const [
                ButtonSegment(value: EnergySex.male, label: Text('Мужской')),
                ButtonSegment(value: EnergySex.female, label: Text('Женский')),
              ],
              selected: {if (profile.sex != null) profile.sex!},
              onSelectionChanged: (selection) =>
                  _saveProfile((p) => p.copyWith(sex: selection.first)),
            ),
            const SizedBox(height: CMSpacing.sp3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _birthYearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Год рождения',
                      isDense: true,
                    ),
                    onChanged: (text) {
                      final year = int.tryParse(text.trim());
                      final now = DateTime.now().year;
                      if (text.trim().isEmpty) {
                        _saveProfile((p) => p.copyWith(clearBirthYear: true));
                      } else if (year != null && year >= 1900 && year <= now - 13) {
                        _saveProfile((p) => p.copyWith(birthYear: year));
                      }
                    },
                  ),
                ),
                const SizedBox(width: CMSpacing.sp3),
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Рост, см',
                      isDense: true,
                    ),
                    onChanged: (text) {
                      final cm = double.tryParse(text.replaceAll(',', '.'));
                      if (text.trim().isEmpty) {
                        _saveProfile((p) => p.copyWith(clearHeightCm: true));
                      } else if (cm != null && cm >= 100 && cm <= 250) {
                        _saveProfile((p) => p.copyWith(heightCm: cm));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: CMSpacing.sp2),
            Text(
              'Рост подставляется из Health Connect; пол и возраст HC не '
              'хранит — нужны для формулы BMR. Без профиля расход считается '
              'по записям HC, если они есть.',
              style: CMFonts.body(size: 12, color: colors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Блок «Расход калорий» (Фаза 7, B.4): 4 строки-компонента — источник и
/// значение каждого, кнопка «⋯» раскрывает инлайн-редактор оверрайда под
/// строкой (решение пользователя 2026-09-14). Внизу — «Итого сегодня».
class ExpenditureBlock extends StatefulWidget {
  const ExpenditureBlock({super.key});

  @override
  State<ExpenditureBlock> createState() => _ExpenditureBlockState();
}

class _ExpenditureBlockState extends State<ExpenditureBlock> {
  /// Индекс раскрытой строки (0=BMR, 1=шаги, 2=силовые, 3=бытовой).
  int? _expanded;

  void _toggle(int index) => setState(() => _expanded = _expanded == index ? null : index);

  void _saveProfile(ExpenditureProfile Function(ExpenditureProfile) change) {
    context.read<DashboardViewModel>().setEnergyProfile(
          change(context.read<DashboardViewModel>().energyProfile),
        );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final colors = context.cmColors;
    final profile = vm.energyProfile;
    final today = DateKey(DateTime.now());
    final exp = vm.expenditureFor(today);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CMSpacing.sp4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Расход калорий',
                style: CMFonts.heading(size: 16, color: colors.ink)),
            const SizedBox(height: CMSpacing.sp2),

            // ── Базальный (BMR) ──
            _row(
              name: 'Базальный (BMR)',
              source: switch (vm.bmrSourceForToday) {
                BmrSource.manual => 'Вручную',
                BmrSource.healthConnect => 'Health Connect',
                BmrSource.mifflin => 'Формула Mifflin-St Jeor',
                BmrSource.none => 'Укажите профиль или подключите HC',
              },
              value: exp == null ? '—' : formatThousands(exp.bmrKcal),
              unit: 'ккал/день',
              expanded: _expanded == 0,
              onToggle: () => _toggle(0),
              editor: _bmrEditor(profile),
            ),

            // ── Шаги ──
            _row(
              name: 'Шаги',
              source: '${profile.stepsKcalPerKgPerStep} ккал/кг/шаг · нетто-ходьба',
              value: vm.kcalPer1000Steps == null
                  ? '—'
                  : '≈${vm.kcalPer1000Steps!.toStringAsFixed(1)}',
              unit: 'ккал/1000 шагов',
              expanded: _expanded == 1,
              onToggle: () => _toggle(1),
              editor: _stepsEditor(vm),
            ),

            // ── Силовые ──
            _row(
              name: 'Силовые',
              source: profile.trainingKcalPerSession != null
                  ? 'Своя сессия · ${profile.trainingKcalPerSession!.toStringAsFixed(0)} ккал'
                  : 'Compendium · ${profile.trainingIntensity == TrainingIntensity.moderate ? '3.5' : '6.0'} MET '
                      '(${profile.trainingIntensity == TrainingIntensity.moderate ? 'умеренная' : 'тяжёлая'})',
              value: exp == null ? '—' : '≈${formatThousands(exp.trainingKcal)}',
              unit: 'ккал/день',
              expanded: _expanded == 2,
              onToggle: () => _toggle(2),
              editor: _trainingEditor(profile),
            ),

            // ── Бытовой ──
            _row(
              name: 'Бытовой',
              source: 'TEF + мелкая активность',
              value: formatThousands(profile.householdKcal),
              unit: 'ккал/день',
              expanded: _expanded == 3,
              onToggle: () => _toggle(3),
              editor: _householdEditor(profile),
            ),

            // ── Итого сегодня ──
            const SizedBox(height: CMSpacing.sp2),
            Divider(color: colors.outline, height: 1),
            const SizedBox(height: CMSpacing.sp2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Итого сегодня',
                    style: CMFonts.caption(size: 11, color: colors.noise)),
                Text.rich(
                  TextSpan(
                    text: exp == null ? '—' : '≈ ${formatThousands(exp.total)}',
                    style: CMFonts.metric(size: 20, color: colors.signal),
                    children: [
                      TextSpan(
                        text: ' ккал/день',
                        style: CMFonts.caption(size: 11, color: colors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Строка компонента: имя + источник, значение + юнит, «⋯» раскрывает
  /// инлайн-редактор (решение пользователя — раскрытие под строкой).
  Widget _row({
    required String name,
    required String source,
    required String value,
    required String unit,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget editor,
  }) {
    final colors = context.cmColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: CMSpacing.sp2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: CMFonts.label(size: 15, color: colors.ink)),
                    const SizedBox(height: 2),
                    Text(source,
                        style: CMFonts.caption(size: 10.5, color: colors.noise)),
                  ],
                ),
              ),
              const SizedBox(width: CMSpacing.sp2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value,
                      style: CMFonts.metric(size: 16, color: colors.ink)),
                  Text(unit,
                      style: CMFonts.caption(size: 10, color: colors.inkMuted)),
                ],
              ),
              IconButton(
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.more_vert,
                  size: 20,
                  color: colors.noise,
                ),
                tooltip: 'Настроить',
                onPressed: onToggle,
              ),
            ],
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: CMSpacing.sp2),
            padding: const EdgeInsets.all(CMSpacing.sp3),
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(CMRadius.md),
              border: Border.all(color: colors.outline),
            ),
            child: editor,
          ),
      ],
    );
  }

  /// Редактор BMR: режим авто/вручную + значение ккал/день.
  Widget _bmrEditor(ExpenditureProfile profile) {
    final controller = TextEditingController(
      text: profile.bmrManualKcal?.toStringAsFixed(0) ?? '',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<BmrMode>(
          segments: const [
            ButtonSegment(value: BmrMode.auto, label: Text('Авто')),
            ButtonSegment(value: BmrMode.manual, label: Text('Вручную')),
          ],
          selected: {profile.bmrMode},
          onSelectionChanged: (selection) =>
              _saveProfile((p) => p.copyWith(bmrMode: selection.first)),
        ),
        if (profile.bmrMode == BmrMode.manual) ...[
          const SizedBox(height: CMSpacing.sp2),
          TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'ккал/день',
              isDense: true,
            ),
            onChanged: (text) {
              final kcal = double.tryParse(text.replaceAll(',', '.'));
              if (kcal != null && kcal > 0) {
                _saveProfile((p) => p.copyWith(bmrManualKcal: kcal));
              }
            },
          ),
        ],
      ],
    );
  }

  /// Редактор шагов (§0 п. 14): вводится «ккал на 1000 шагов», хранится
  /// коэффициент = значение ÷ (последний резолвленный вес × 1000).
  Widget _stepsEditor(DashboardViewModel vm) {
    final colors = context.cmColors;
    final weight = vm.latestWeightKg;
    if (weight == null) {
      return Text(
        'Нужен хотя бы один вес — коэффициент зависит от веса.',
        style: CMFonts.body(size: 12, color: colors.inkMuted),
      );
    }
    final controller = TextEditingController(
      text: vm.kcalPer1000Steps!.toStringAsFixed(1),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'ккал на 1000 шагов',
            isDense: true,
          ),
          onChanged: (text) {
            final kcal = double.tryParse(text.replaceAll(',', '.'));
            if (kcal == null || kcal <= 0) return;
            _saveProfile((p) =>
                p.copyWith(stepsKcalPerKgPerStep: kcal / (weight * 1000)));
          },
        ),
      ],
    );
  }

  /// Редактор силовых: частота (степпер 0–7), длительность, интенсивность
  /// (умеренная/тяжёлая) или своя ккал/сессия.
  Widget _trainingEditor(ExpenditureProfile profile) {
    final durationController = TextEditingController(
      text: profile.trainingDurationMin.toString(),
    );
    final ownController = TextEditingController(
      text: profile.trainingKcalPerSession?.toStringAsFixed(0) ?? '',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Частота, раз/нед',
                      style:
                          CMFonts.caption(size: 11, color: context.cmColors.inkMuted)),
                  const SizedBox(height: CMSpacing.sp1),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => _saveProfile((p) => p.copyWith(
                            trainingFreqPerWeek: (p.trainingFreqPerWeek - 1).clamp(0, 7))),
                        child: const Icon(Icons.remove, size: 16),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: CMSpacing.sp3),
                        child: Text(
                          '${profile.trainingFreqPerWeek}',
                          style: CMFonts.metric(
                              size: 20, color: context.cmColors.ink),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => _saveProfile((p) => p.copyWith(
                            trainingFreqPerWeek: (p.trainingFreqPerWeek + 1).clamp(0, 7))),
                        child: const Icon(Icons.add, size: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: CMSpacing.sp3),
            Expanded(
              child: TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Длительность, мин',
                  isDense: true,
                ),
                onChanged: (text) {
                  final min = int.tryParse(text.trim());
                  if (min != null && min >= 5 && min <= 300) {
                    _saveProfile((p) => p.copyWith(trainingDurationMin: min));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: CMSpacing.sp2),
        SegmentedButton<TrainingIntensity>(
          segments: const [
            ButtonSegment(value: TrainingIntensity.moderate, label: Text('Умеренная')),
            ButtonSegment(value: TrainingIntensity.heavy, label: Text('Тяжёлая')),
          ],
          selected: {profile.trainingIntensity},
          onSelectionChanged: (selection) => _saveProfile(
              (p) => p.copyWith(trainingIntensity: selection.first)),
        ),
        const SizedBox(height: CMSpacing.sp2),
        TextField(
          controller: ownController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Или своя, ккал/сессия',
            isDense: true,
          ),
          onChanged: (text) {
            final t = text.trim();
            if (t.isEmpty) {
              _saveProfile((p) => p.copyWith(clearTrainingKcalPerSession: true));
              return;
            }
            final kcal = double.tryParse(t.replaceAll(',', '.'));
            if (kcal != null && kcal > 0) {
              _saveProfile((p) => p.copyWith(trainingKcalPerSession: kcal));
            }
          },
        ),
      ],
    );
  }

  /// Редактор бытового расхода: ккал/день.
  Widget _householdEditor(ExpenditureProfile profile) {
    final controller = TextEditingController(
      text: profile.householdKcal.toStringAsFixed(0),
    );
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'ккал/день',
        isDense: true,
      ),
      onChanged: (text) {
        final kcal = double.tryParse(text.replaceAll(',', '.'));
        if (kcal != null && kcal >= 0 && kcal <= 1000) {
          _saveProfile((p) => p.copyWith(householdKcal: kcal));
        }
      },
    );
  }
}
