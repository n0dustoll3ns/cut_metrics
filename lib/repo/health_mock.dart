import 'package:cut_metrics/repo/health.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Mock-реализация HealthRepository для тестирования UI
class MockHealthRepository extends HealthRepository {
  @override
  Future<bool> checkAndRequestPermissions(List<HealthDataType> types) async {
    debugPrint("🟢 Mock: permissions always granted");
    return true;
  }

  @override
  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    debugPrint("📊 Mock: returning data for $startDate – $endDate");

    return _generateMockData(types, startDate, endDate);
  }

  List<HealthDataPoint> _generateMockData(List<HealthDataType> types, DateTime startDate, DateTime endDate) {
    final points = <HealthDataPoint>[];

    // Генерируем данные для каждого дня в диапазоне
    for (
      var day = startDate;
      day.isBefore(endDate) || day.isAtSameMomentAs(endDate);
      day = day.add(const Duration(days: 1))
    ) {
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));

      for (final type in types) {
        switch (type) {
          case HealthDataType.WEIGHT:
            points.add(
              HealthDataPoint(
                sourceName: 'com.google.android.apps.fitness',
                uuid: '',
                sourceDeviceId: '',
                sourceId: '',
                sourcePlatform: HealthPlatformType.googleHealthConnect,
                value: NumericHealthValue(numericValue: 70.0 + (day.day % 5) * 0.5 - 2.0),
                dateFrom: dayStart,
                dateTo: dayEnd,
                type: type,
                unit: HealthDataUnit.KILOGRAM,
              ),
            );
            break;

          case HealthDataType.STEPS:
            points.add(
              HealthDataPoint(
                sourceName: 'com.google.android.apps.fitness',
                uuid: '',

                sourceDeviceId: '',
                sourceId: '',
                sourcePlatform: HealthPlatformType.googleHealthConnect,
                value: NumericHealthValue(numericValue: 8000 + (day.day % 7) * 500),
                dateFrom: dayStart,
                dateTo: dayEnd,
                type: type,
                unit: HealthDataUnit.COUNT,
              ),
            );
            break;

          case HealthDataType.NUTRITION:
          case HealthDataType.DIETARY_ENERGY_CONSUMED:
            points.add(
              HealthDataPoint(
                sourceName: 'com.google.android.apps.fitness',
                uuid: '',

                sourceDeviceId: '',
                sourceId: '',
                sourcePlatform: HealthPlatformType.googleHealthConnect,
                value: NutritionHealthValue(
                  calories: 2000.0 + (day.day % 3) * 100,
                  protein: 80.0 + (day.day % 5) * 10,
                  fat: 65.0 + (day.day % 4) * 5,
                  carbs: 250.0 + (day.day % 6) * 20,
                ),
                dateFrom: dayStart,
                dateTo: dayEnd,
                type: HealthDataType.NUTRITION,
                unit: HealthDataUnit.KILOCALORIE,
              ),
            );
            break;

          case HealthDataType.BASAL_ENERGY_BURNED:
            points.add(
              HealthDataPoint(
                sourceName: 'com.google.android.apps.fitness',
                uuid: '',

                sourceDeviceId: '',
                sourceId: '',
                sourcePlatform: HealthPlatformType.googleHealthConnect,
                value: NumericHealthValue(numericValue: 1600.0 + (day.day % 4) * 50),
                dateFrom: dayStart,
                dateTo: dayEnd,
                type: type,
                unit: HealthDataUnit.KILOCALORIE,
              ),
            );
            break;

          case HealthDataType.ACTIVE_ENERGY_BURNED:
            points.add(
              HealthDataPoint(
                sourceName: 'com.google.android.apps.fitness',
                uuid: '',

                sourceDeviceId: '',
                sourceId: '',
                sourcePlatform: HealthPlatformType.googleHealthConnect,
                value: NumericHealthValue(numericValue: 400.0 + (day.day % 5) * 100),
                dateFrom: dayStart,
                dateTo: dayEnd,
                type: type,
                unit: HealthDataUnit.KILOCALORIE,
              ),
            );
            break;

          case HealthDataType.SLEEP_DEEP:
            points.add(
              HealthDataPoint(
                sourceName: 'com.google.android.apps.fitness',
                uuid: '',

                sourceDeviceId: '',
                sourceId: '',
                sourcePlatform: HealthPlatformType.googleHealthConnect,
                value: NumericHealthValue(numericValue: 90.0 + (day.day % 3) * 10),
                dateFrom: dayStart.add(const Duration(hours: 23, minutes: 30)),
                dateTo: dayStart.add(const Duration(hours: 2)),
                type: type,
                unit: HealthDataUnit.MINUTE,
              ),
            );
            break;

          case HealthDataType.SLEEP_LIGHT:
            points.add(
              HealthDataPoint(
                sourceName: 'com.google.android.apps.fitness',
                uuid: '',

                sourceDeviceId: '',
                sourceId: '',
                sourcePlatform: HealthPlatformType.googleHealthConnect,
                value: NumericHealthValue(numericValue: 240.0 + (day.day % 4) * 15),
                dateFrom: dayStart.add(const Duration(hours: 23, minutes: 30)),
                dateTo: dayStart.add(const Duration(hours: 7)),
                type: type,
                unit: HealthDataUnit.MINUTE,
              ),
            );
            break;

          case HealthDataType.SLEEP_REM:
            points.add(
              HealthDataPoint(
                sourceName: 'com.google.android.apps.fitness',
                uuid: '',

                sourceDeviceId: '',
                sourceId: '',
                sourcePlatform: HealthPlatformType.googleHealthConnect,
                value: NumericHealthValue(numericValue: 60.0 + (day.day % 5) * 5),
                dateFrom: dayStart.add(const Duration(hours: 23, minutes: 30)),
                dateTo: dayStart.add(const Duration(hours: 7)),
                type: type,
                unit: HealthDataUnit.MINUTE,
              ),
            );
            break;

          default:
            break;
        }
      }
    }

    debugPrint("📊 Mock: generated ${points.length} points");
    return points;
  }
}

// /// Вспомогательный класс для значения питания, так как
// /// стандартный NutritionHealthValue может не быть доступен
// class _MockNutritionValue implements HealthValue {
//   final double? calories;
//   final double? protein;
//   final double? fat;
//   final double? carbs;

//   _MockNutritionValue({this.calories, this.protein, this.fat, this.carbs});

//   @override
//   String? $type;

//   @override
//   // TODO: implement fromJsonFunction
//   Function get fromJsonFunction => throw UnimplementedError();

//   @override
//   // TODO: implement jsonType
//   String get jsonType => throw UnimplementedError();

//   @override
//   Map<String, dynamic> toJson() {
//     // TODO: implement toJson
//     throw UnimplementedError();
//   }
// }
