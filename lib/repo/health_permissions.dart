import 'package:health/health.dart';

/// Sleep-типы, поддерживаемые Health Connect на Android.
///
/// Все запрашиваются в `READ` — сон остаётся read-only (Фаза 2, секция 2).
const List<HealthDataType> kSleepTypes = [
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_AWAKE_IN_BED,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_IN_BED,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_OUT_OF_BED,
  HealthDataType.SLEEP_REM,
  HealthDataType.SLEEP_SESSION,
  HealthDataType.SLEEP_UNKNOWN,
];

/// Все типы данных, которые приложение запрашивает у Health Connect.
///
/// WEIGHT и STEPS — `READ_WRITE` (ручной ввод пишется в Health Connect).
/// Остальные — `READ` (сон, питание).
List<HealthDataType> get kHealthDataTypes => [
  HealthDataType.WEIGHT,
  HealthDataType.STEPS,
  ...kSleepTypes,
  HealthDataType.NUTRITION,
];

/// Разрешения для [kHealthDataTypes] в том же порядке.
///
/// WEIGHT и STEPS — `READ_WRITE` (Фаза 2: запись ручного ввода в Health Connect).
/// Сон и питание — `READ` (read-only, не трогаем).
List<HealthDataAccess> get kHealthDataAccess => [
  HealthDataAccess.READ_WRITE, // WEIGHT
  HealthDataAccess.READ_WRITE, // STEPS
  ...kSleepTypes.map((_) => HealthDataAccess.READ),
  HealthDataAccess.READ, // NUTRITION
];

/// Запрашивает разрешения у Health Connect.
///
/// WEIGHT и STEPS запрашиваются с `READ_WRITE` (для записи ручного ввода),
/// остальные типы — с `READ`.
///
/// Возвращает `true` при успехе, `false` — если пользователь отказал
/// или Health Connect недоступен. В случае исключения (Health Connect
/// не установлен и т.п.) — пробрасывает наверх, не глушит.
///
/// Перед вызовом рекомендуется проверить [Health.hasPermissions],
/// т.к. повторный запрос при уже выданных правах может блокировать
/// (особенно на iOS, см. документацию пакета `health`).
Future<bool> checkAndRequestPermissions(Health health) async {
  return await health.requestAuthorization(
    kHealthDataTypes,
    permissions: kHealthDataAccess,
  );
}