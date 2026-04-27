import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:health_widgets/vm.dart';
import 'package:health_widgets/widgets/legend_item.dart';
import 'package:health_widgets/widgets/painter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  final GlobalKey _boundaryKey = GlobalKey();

  /// Метод UI-слоя для создания скриншота и передачи пути во ViewModel
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
      final file = await File('${tempDir.path}/sleep_chart.png').create();
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (context.mounted) {
        context.read<SleepViewModel>().updateSystemWidget(file.path);
      }
    } catch (e) {
      debugPrint("Screenshot failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SleepViewModel(),
      child: Consumer<SleepViewModel>(
        builder: (context, viewModel, child) {
          // Слушаем изменения данных для обновления виджета
          // Используем addPostFrameCallback, чтобы убедиться, что UI отрисовался перед скриншотом
          if (viewModel.sleepData.isNotEmpty && !viewModel.isLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _captureAndUpdateWidget();
            });
          }

          return Scaffold(
            appBar: AppBar(title: const Text('Sleep Analytics'), centerTitle: true),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Last ${viewModel.selectedDays} Days",
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        // Селект количества дней
                        DropdownButton<int>(
                          value: viewModel.selectedDays,
                          underline: Container(),
                          items: List.generate(
                            7,
                            (index) => index + 1,
                          ).map((d) => DropdownMenuItem(value: d, child: Text("$d d"))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              viewModel.setSelectedDays(val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Индикатор загрузки или График
                    if (viewModel.isLoading)
                      const Center(child: CircularProgressIndicator())
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
                              child: CustomPaint(painter: MultiPhaseSleepPainter(viewModel.sleepData)),
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                    const Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        LegendItem(color: Color(0xFF1A237E), label: "Deep"),
                        LegendItem(color: Color(0xFF3F51B5), label: "Light"),
                        LegendItem(color: Color(0xFF9FA8DA), label: "REM"),
                      ],
                    ),
                    const Spacer(),

                    // Кнопка обновления
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: FilledButton.icon(
                        onPressed: viewModel.isLoading ? null : viewModel.authorizeAndFetch,
                        icon: viewModel.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(
                          viewModel.isLoading ? 'Syncing...' : 'Update & Sync',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),

                    // Вывод ошибки, если есть
                    if (viewModel.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(viewModel.error!, style: const TextStyle(color: Colors.redAccent)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
