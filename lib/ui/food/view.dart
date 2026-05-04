import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:health_widgets/ui/food/vm.dart';
import 'package:health_widgets/ui/food/widgets/painter.dart';
import 'package:health_widgets/ui/sleep/widgets/legend_item.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class NutitonView extends StatefulWidget {
  const NutitonView({super.key});

  @override
  State<NutitonView> createState() => _NutitonViewState();
}

class _NutitonViewState extends State<NutitonView> {
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
      final file = await File('${tempDir.path}/nutrition_chart.png').create();
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (context.mounted) {
        
        context.read<NutritionViewModel>().updateSystemWidget(file.path);
      }
    } catch (e) {
      debugPrint("Screenshot failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<NutritionViewModel>();
    // Точечная подписка на статус загрузки для кнопки
    final isLoading = context.select((NutritionViewModel vm) => vm.isLoading);

    // Точечная подписка на данные для графика
    // Мы подписываемся на список, чтобы перерисовать график при изменении данных
    final data = context.select((NutritionViewModel vm) => vm.nutritionData);

    // Подписка на выбранное количество дней для заголовка и дропдауна
    final selectedDays = context.select((NutritionViewModel vm) => vm.selectedDays);

    // Подписка на ошибку
    final error = context.select((NutritionViewModel vm) => vm.error);

    // Логика обновления виджета:
    // Если данные есть и мы не загружаемся, планируем скриншот после отрисовки этого кадра.
    // Это заменяет рекурсию и проверки debugNeedsPaint.
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
                    // Вызываем метод VM напрямую через read, так как это действие, а не состояние
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
                    child: CustomPaint(painter: NutritionPainter(data)),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),
          const Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              LegendItem(color: Colors.blue, label: "Proteins"),
              LegendItem(color: Colors.orange, label: "Fats"),
              LegendItem(color: Colors.brown, label: "Carbs"),
            ],
          ),
          const Spacer(),

          // Кнопка обновления
          SizedBox(
            width: double.infinity,
            height: 60,
            child: FilledButton.icon(
              // Блокируем кнопку при загрузке
              onPressed: isLoading ? null : () => vm.authorizeAndFetchNutritionData(),
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
