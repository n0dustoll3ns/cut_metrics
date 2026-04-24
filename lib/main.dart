import 'package:flutter/material.dart';
import 'package:health/health.dart';

void main() {
  runApp(const HealthWidgetsApp());
}

class HealthWidgetsApp extends StatefulWidget {
  const HealthWidgetsApp({super.key});

  @override
  State<HealthWidgetsApp> createState() => _HealthWidgetsAppState();
}

class _HealthWidgetsAppState extends State<HealthWidgetsApp> {
  Future<void> authorizeHealth() async {
    // 1. Проверяем, установлена ли поддержка Health Connect
    // Создаем экземпляр Health
    // В новых версиях плагина используется Health(), в старых HealthFactory()
    Health health = Health();

    // Указываем, что хотим читать сессии сна
    final types = [HealthDataType.SLEEP_SESSION];
    final permissions = [HealthDataAccess.READ]; // Явно говорим, что только читаем

    // Проверяем/запрашиваем разрешения
    bool requested = await health.requestAuthorization(types, permissions: permissions);

    if (requested) {
      print("Доступ к Health Connect получен!");
      _fetchSleepData(); // Переходим к чтению
    } else {
      print("В доступе отказано.");
    }
  }

  Future<void> _fetchSleepData() async {
    Health health = Health();
    var now = DateTime.now();
    var yesterday = now.subtract(Duration(days: 7)); // Берем за неделю

    List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
      types: [HealthDataType.SLEEP_SESSION],
      startTime: yesterday,
      endTime: now,
    );

    print("Получено записей о сне: ${healthData.length}");
    for (var d in healthData) {
      print("Тип: ${d.type}, Значение: ${d.value}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            child: Text('Connect!'),
            onPressed: () {
              authorizeHealth();
            },
          ),
        ),
      ),
    );
  }
}
