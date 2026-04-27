import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:health/health.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const HealthWidgetsApp());
}

class HealthWidgetsApp extends StatefulWidget {
  const HealthWidgetsApp({super.key});

  @override
  State<HealthWidgetsApp> createState() => _HealthWidgetsAppState();
}

class _HealthWidgetsAppState extends State<HealthWidgetsApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  List<double> _sleepData = [];

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
    var now = DateTime.now();
    var range = now.subtract(const Duration(days: 7));

    List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
      types: [HealthDataType.SLEEP_SESSION],
      startTime: range,
      endTime: now,
    );

    setState(() {
      _sleepData = healthData.map((e) {
        final val = (e.value as NumericHealthValue).numericValue.toDouble();
        return val / 60; // Это часы
      }).toList();
    });

    if (_sleepData.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateWidget());
    }
  }

  Future<void> _updateWidget() async {
    try {
      RenderRepaintBoundary boundary =
          _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      var byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/sleep_chart.png').create();
      await file.writeAsBytes(bytes);

      await HomeWidget.saveWidgetData<String>('chart_path', file.path);
      await HomeWidget.updateWidget(name: 'SleepWidgetProvider', androidName: 'SleepWidgetProvider');
    } catch (e) {
      debugPrint("Widget update failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Sleep Tracker')),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            RepaintBoundary(
              key: _boundaryKey,
              child: Container(
                padding: const EdgeInsets.all(16),
                width: 300,
                height: 150,
                color: Colors.black,
                child: CustomPaint(painter: SleepChartPainter(_sleepData)),
              ),
            ),
            const Spacer(),
            ElevatedButton(onPressed: authorizeHealth, child: const Text('Sync & Update Widget')),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}

class SleepChartPainter extends CustomPainter {
  final List<double> data;
  SleepChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) {
       return; 
    }

    final paint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.fill;

    double barWidth = size.width / (data.length * 1.5);
    double maxVal = data.reduce((a, b) => a > b ? a : b);

    for (int i = 0; i < data.length; i++) {
      double barHeight = (data[i] / maxVal) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * barWidth * 1.5, size.height - barHeight, barWidth, barHeight),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
