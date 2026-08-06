import 'package:cut_metrics/old_proj/domain/metric_type.dart';
import 'package:cut_metrics/old_proj/view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Диалог настройки приоритетов источников данных.
///
/// Открывается через [showSourcePriorityDialog].
/// Пользователь выбирает метрику и перетаскивает источники,
/// чтобы задать их приоритет (верх = наивысший).
Future<void> showSourcePriorityDialog(BuildContext context) {
  final vm = context.read<ViewModel>();
  return showDialog<void>(
    context: context,
    builder: (context) =>
        ChangeNotifierProvider.value(value: vm, builder: (context, child) => const _SourcePriorityDialog()),
  );
}

class _SourcePriorityDialog extends StatefulWidget {
  const _SourcePriorityDialog();

  @override
  State<_SourcePriorityDialog> createState() => _SourcePriorityDialogState();
}

class _SourcePriorityDialogState extends State<_SourcePriorityDialog> {
  MetricType _selectedMetric = MetricType.weight;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<ViewModel>();

    return AlertDialog(
      title: const Text('Приоритеты источников'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Выбор метрики
            DropdownButton<MetricType>(
              value: _selectedMetric,
              isExpanded: true,
              items: MetricType.values.map((m) => DropdownMenuItem(value: m, child: Text(m.label))).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedMetric = value);
                }
              },
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Перетащите источники, чтобы изменить приоритет.\nВерх списка = наивысший приоритет.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
            const SizedBox(height: 8),
            // Список источников для выбранной метрики
            Flexible(
              child: _SourceReorderableList(metric: _selectedMetric, vm: vm),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Закрыть'))],
    );
  }
}

/// Перетаскиваемый список источников для одной метрики.
class _SourceReorderableList extends StatefulWidget {
  final MetricType metric;
  final ViewModel vm;

  const _SourceReorderableList({required this.metric, required this.vm});

  @override
  State<_SourceReorderableList> createState() => _SourceReorderableListState();
}

class _SourceReorderableListState extends State<_SourceReorderableList> {
  void _onReorderItem(int oldIndex, int newIndex, List<String> sources) {
    final item = sources.removeAt(oldIndex);
    sources.insert(newIndex, item);
    // Сохраняем и пересчитываем
    widget.vm.setSourcePriorities(widget.metric, sources);
  }

  @override
  Widget build(BuildContext context) {
    final sources = context.select(
      (ViewModel vm) => switch (widget.metric) {
        MetricType.weight =>
          vm.getWeightSourcePriorities().isEmpty ? vm.weightSources : vm.getWeightSourcePriorities(),
        MetricType.steps =>
          vm.getStepsSourcePriorities().isEmpty ? vm.stepsSources : vm.getStepsSourcePriorities(),
        MetricType.sleep =>
          vm.getSleepSourcePriorities().isEmpty ? vm.sleepSources : vm.getSleepSourcePriorities(),
        MetricType.nutrition =>
          vm.getNutritionSourcePriorities().isEmpty ? vm.nutritionSources : vm.getNutritionSourcePriorities(),
      },
    );
    if (sources.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Нет данных об источниках.\nЗагрузите данные хотя бы один раз.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: sources.length,
      onReorderItem: (i1, i2) => _onReorderItem(i1, i2, sources),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final source = sources[index];
        return ListTile(
          key: ValueKey('$index-$source'),
          leading: CircleAvatar(
            backgroundColor: index == 0 ? Colors.orangeAccent : Colors.grey[700],
            child: Text(
              '${index + 1}',
              style: TextStyle(color: index == 0 ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(source, style: TextStyle(fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal)),
          trailing: ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_indicator, color: Colors.white54),
          ),
        );
      },
    );
  }
}
