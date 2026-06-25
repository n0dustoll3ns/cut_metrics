import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthRepository {
  final Health _health = Health();
  bool _isConfigured = false;

  Future<void> ensureConfigured() async {
    if (!_isConfigured) {
      debugPrint("🔧 Configuring Health Client...");
      await _health.configure();
      _isConfigured = true;
      debugPrint("✅ Health Client Configured");
    }
  }

  Future<bool> checkAndRequestPermissions(List<HealthDataType> types) async {
    await ensureConfigured();

    // 1. Проверка статуса SDK
    var status = await _health.getHealthConnectSdkStatus();
    debugPrint("📱 Health Connect SDK Status: $status");

    if (status != HealthConnectSdkStatus.sdkAvailable) {
      debugPrint("❌ SDK NOT Available. User needs to install Health Connect app.");
      // Можно попробовать предложить установку:
      // await _health.installHealthConnect();
      return false;
    }

    // 2. Проверка текущих прав
    final permissions = List.filled(types.length, HealthDataAccess.READ);
    bool? hasPermissions = await _health.hasPermissions(types, permissions: permissions);
    debugPrint("🔐 Has Permissions: $hasPermissions");

    if (hasPermissions == true) {
      return true;
    }

    // 3. Попытка запроса
    debugPrint("🚀 Requesting Authorization for types: $types");
    try {
      bool granted = await _health.requestAuthorization(types, permissions: permissions);
      debugPrint("🏁 Authorization Result: $granted");
      return granted;
    } catch (e, stackTrace) {
      debugPrint("💥 Error requesting auth: $e");
      debugPrint(stackTrace.toString());
      return false;
    }
  }

  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await ensureConfigured();
    return await _health.getHealthDataFromTypes(types: types, startTime: startDate, endTime: endDate);
  }



    /// Получение агрегированных данных о шагах по дням (устраняет дубликаты)
  /// Возвращает `Map<String, int>` где ключ - дата в формате "YYYY-MM-DD", значение - количество шагов
  Future<Map<String, int>> fetchAggregatedSteps({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await ensureConfigured();

    final Map<String, int> dailySteps = {};

    // Итерируем по каждому дню в диапазоне
    DateTime currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final endDateNormalized = DateTime(endDate.year, endDate.month, endDate.day);

    while (currentDate.isBefore(endDateNormalized) || currentDate.isAtSameMomentAs(endDateNormalized)) {
      try {
        // Начало дня: 00:00:00
        final dayStart = DateTime(currentDate.year, currentDate.month, currentDate.day);
        // Конец дня: 23:59:59.999
        final dayEnd = DateTime(currentDate.year, currentDate.month, currentDate.day, 23, 59, 59, 999);

        debugPrint(
          "📊 Fetching steps for $currentDate (${dayStart.toIso8601String()} - ${dayEnd.toIso8601String()})",
        );

        // Используем getTotalStepsInInterval для получения агрегированных данных за день
        // Health Connect автоматически устранит дубликаты на основе приоритетов источников
        final stepsCount = await _health.getTotalStepsInInterval(dayStart, dayEnd);

        if (stepsCount != null && stepsCount > 0) {
          final dateKey =
              "${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}";
          dailySteps[dateKey] = stepsCount;
          debugPrint("✅ Steps for $dateKey: $stepsCount");
        } else {
          debugPrint("⚠️ No steps data for $currentDate");
        }
      } catch (e) {
        debugPrint("❌ Error fetching steps for $currentDate: $e");
      }

      // Переходим к следующему дню
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return dailySteps;
  }
}
