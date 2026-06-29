import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthRepository {
  final Health _health = Health();

  // РЕФАКТОРИНГ: мемоизированный Future вместо bool-флага.
  // Защищает от двойного вызова configure() при параллельных запросах.
  Future<void>? _configFuture;

  Future<void> ensureConfigured() {
    return _configFuture ??= _doConfigured();
  }

  Future<void> _doConfigured() async {
    debugPrint('🔧 Configuring Health Client...');
    await _health.configure();
    debugPrint('✅ Health Client Configured');
  }

  Future<bool> checkAndRequestPermissions(List<HealthDataType> types) async {
    await ensureConfigured();

    // 1. Проверка статуса SDK
    final status = await _health.getHealthConnectSdkStatus();
    debugPrint('📱 Health Connect SDK Status: $status');

    if (status != HealthConnectSdkStatus.sdkAvailable) {
      debugPrint('❌ SDK NOT Available. User needs to install Health Connect app.');
      return false;
    }

    // 2. Проверка текущих прав
    final permissions = List.filled(types.length, HealthDataAccess.READ);
    final bool? hasPermissions = await _health.hasPermissions(types, permissions: permissions);
    debugPrint('🔐 Has Permissions: $hasPermissions');

    if (hasPermissions == true) return true;

    // 3. Попытка запроса
    debugPrint('🚀 Requesting Authorization for types: $types');
    try {
      final granted = await _health.requestAuthorization(types, permissions: permissions);
      debugPrint('🏁 Authorization Result: $granted');
      return granted;
    } catch (e, stackTrace) {
      debugPrint('💥 Error requesting auth: $e');
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
    return _health.getHealthDataFromTypes(types: types, startTime: startDate, endTime: endDate);
  }
}
