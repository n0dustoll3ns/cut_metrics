import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:health_widgets/ui/weight/vm.dart';
import 'package:health_widgets/ui/weight/widgets/painter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class WeightView extends StatefulWidget {
  const WeightView({super.key});

  @override
  State<WeightView> createState() => _WeightViewState();
}

class _WeightViewState extends State<WeightView> {
  final GlobalKey _boundaryKey = GlobalKey();

  /// Метод UI-слоя для создания скриншота и передачи пути во vm
  Future<void> _captureAndUpdateWidget() async {
    final context = _boundaryKey.currentContext;
    if (context == null) return;

    try {
      // К этому моменту кадр уже отрисован благодаря addPostFrameCallback
      RenderRepaintBoundary boundary = context.findRenderObject() as RenderRepaintBoundary;

      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      var byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/weight_chart.png').create();
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (context.mounted) {
        context.read<WeightViewModel>().updateSystemWidget(file.path);
      }
    } catch (e) {
      debugPrint("Screenshot failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<WeightViewModel>();
    // Точечная подписка на статус загрузки для кнопки
    final isLoading = context.select((WeightViewModel vm) => vm.isLoading);

    // Точечная подписка на данные для графика
    final data = context.select((WeightViewModel vm) => vm.weightData);

    // Подписка на выбранное количество дней для заголовка и дропдауна
    final selectedDays = context.select((WeightViewModel vm) => vm.selectedDays);

    // Подписка на средний вес
    final averageWeight = context.select((WeightViewModel vm) => vm.averageWeight);

    // Подписка на ошибку
    final error = context.select((WeightViewModel vm) => vm.error);

    // Логика обновления виджета:
    // Если данные есть и мы не загружаемся, планируем скриншот после отрисовки этого кадра.
    if (data.isNotEmpty && !isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _captureAndUpdateWidget();
      });
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Last $selectedDays Days",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              // Селект количества дней
              DropdownButton<int>(
                value: selectedDays,
                underline: Container(),
                items: List.generate(
                  7,
                  (index) => index + 1,
                ).map((d) => DropdownMenuItem(value: d, child: Text("$d d"))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    vm.setSelectedDays(val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Индикатор загрузки или График
          if (isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Card(
              elevation: 0,
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: Container(
                    width: double.infinity,
                    height: 250,
                    color: Colors.transparent,
                    child: CustomPaint(painter: WeightPainter(data)),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),
          
          // Отображение среднего веса
          if (averageWeight != null)
            Card(
              elevation: 0,
              color: Colors.grey[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.monitor_weight_outlined, color: Colors.greenAccent),
                    const SizedBox(width: 12),
                    Text(
                      'Average: ${averageWeight.toStringAsFixed(1)} kg',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          const Spacer(),

          // Кнопка обновления
          SizedBox(
            width: double.infinity,
            height: 60,
            child: FilledButton.icon(
              // Блокируем кнопку при загрузке
              onPressed: isLoading ? null : () => vm.authorizeAndFetchWeightData(),
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(isLoading ? 'Syncing...' : 'Update & Sync', style: const TextStyle(fontSize: 16)),
            ),
          ),

          // Вывод ошибки, если есть
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(error, style: const TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }
}
