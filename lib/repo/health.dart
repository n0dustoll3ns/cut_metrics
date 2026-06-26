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
}
