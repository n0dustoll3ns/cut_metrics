import 'dart:io';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:health/health.dart';
import 'package:health_widgets/domain.dart';
import 'package:health_widgets/widgets/legend_item.dart';
import 'package:health_widgets/widgets/painter.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  List<SleepDay> _sleepData = [];
  int _selectedDays = 7; // Состояние для выбора количества дней

  Future<void> authorizeHealth() async {
    Health health = Health();
    await health.configure();
    var status = await health.getHealthConnectSdkStatus();
    if (status != HealthConnectSdkStatus.sdkAvailable) return;

    final types = [HealthDataType.SLEEP_SESSION];
    final permissions = [HealthDataAccess.READ];

    try {
      bool? hasPermissions = await health.hasPermissions(types, permissions: permissions);
      if (hasPermissions == false) {
        bool requested = await health.requestAuthorization(types, permissions: permissions);
        if (!requested) return;
      }
      _fetchSleepData();
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _fetchSleepData() async {
    Health health = Health();
    await health.configure();
    final now = DateTime.now();
    // Используем выбранное количество дней
    final range = DateTime(now.year, now.month, now.day).subtract(Duration(days: _selectedDays - 1));

    List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
      types: [HealthDataType.SLEEP_SESSION],
      startTime: range,
      endTime: now,
    );

    // ГРУППИРОВКА: Собираем данные по дням
    Map<DateTime, List<HealthDataPoint>> grouped = groupBy(healthData, (point) {
      return DateTime(point.dateFrom.year, point.dateFrom.month, point.dateFrom.day);
    });

    List<SleepDay> processedData = [];

    // Проходим по каждой дате в выбранном интервале
    for (int i = 0; i < _selectedDays; i++) {
      DateTime date = range.add(Duration(days: i));
      DateTime key = DateTime(date.year, date.month, date.day);

      double dayDeep = 0, dayLight = 0, dayRem = 0;

      if (grouped.containsKey(key)) {
        for (var point in grouped[key]!) {
          print('point = ${point}');
          double totalHours = (point.value as NumericHealthValue).numericValue.toDouble() / 60;
          // Распределяем фазы (как в вашем примере)
          dayDeep += totalHours * 0.25;
          dayLight += totalHours * 0.55;
          dayRem += totalHours * 0.20;
        }
      }

      processedData.add(SleepDay(date: key, deep: dayDeep, light: dayLight, rem: dayRem));
    }

    setState(() {
      _sleepData = processedData;
    });

    if (_sleepData.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateWidget());

      print('_sleepData = ${_sleepData}');
    }
  }

  Future<void> _updateWidget() async {
    try {
      final context = _boundaryKey.currentContext;
      if (context == null) return;

      RenderRepaintBoundary boundary = context.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      var byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/sleep_chart.png').create();
      await file.writeAsBytes(byteData!.buffer.asUint8List());

      await HomeWidget.saveWidgetData<String>('chart_path', file.path);
      await HomeWidget.updateWidget(name: 'SleepWidgetProvider', androidName: 'SleepWidgetProvider');
    } catch (e) {
      debugPrint("Widget update failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    "Last $_selectedDays Days",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  // Селект количества дней
                  DropdownButton<int>(
                    value: _selectedDays,
                    underline: Container(),
                    items: List.generate(
                      7,
                      (index) => index + 1,
                    ).map((d) => DropdownMenuItem(value: d, child: Text("$d d"))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedDays = val);
                        _fetchSleepData();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                      child: CustomPaint(painter: MultiPhaseSleepPainter(_sleepData)),
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
              SizedBox(
                width: double.infinity,
                height: 60,
                child: FilledButton.icon(
                  onPressed: authorizeHealth,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Update & Sync', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
