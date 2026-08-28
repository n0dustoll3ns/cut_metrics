import 'package:cut_metrics/services/debug_log.dart';
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

/// Одна метрика здоровья для раздельной проверки разрешений (2026-08-28).
///
/// Раньше все 13 типов проверялись одним пакетным вызовом `hasPermissions` —
/// в логах было видно только общее true/false, без детализации, какой именно
/// тип не выдан. Теперь тихая проверка ([checkPermissionsPerType]) идёт
/// отдельным вызовом на КАЖДЫЙ тип (в т.ч. на каждую стадию сна), и значение
/// каждого пермишена пишется в DebugLog с тегом `perm`.
class HealthPermissionGroup {
  /// Человекочитаемое имя метрики («Вес», «Шаги», «Сон», «Питание»).
  final String label;

  /// Типы данных Health Connect, входящие в метрику.
  final List<HealthDataType> types;

  /// Доступы для [types] в том же порядке (READ / READ_WRITE).
  final List<HealthDataAccess> permissions;

  const HealthPermissionGroup({
    required this.label,
    required this.types,
    required this.permissions,
  });
}

/// Группы типов по метрикам — по одной на каждую метрику здоровья.
///
/// Порядок групп задаёт порядок в [kHealthDataTypes]: ровно те же 13 типов,
/// что и раньше (состав запроса и правило «все обязаны быть выданы»
/// не меняются — разделяются только тихие проверки и логи).
const List<HealthPermissionGroup> kPermissionGroups = [
  HealthPermissionGroup(
    label: 'Вес',
    types: [HealthDataType.WEIGHT],
    permissions: [HealthDataAccess.READ_WRITE], // ручной ввод пишется в HC
  ),
  HealthPermissionGroup(
    label: 'Шаги',
    types: [HealthDataType.STEPS],
    permissions: [HealthDataAccess.READ_WRITE], // ручной ввод пишется в HC
  ),
  HealthPermissionGroup(
    label: 'Сон',
    types: kSleepTypes,
    permissions: [
      HealthDataAccess.READ, // SLEEP_ASLEEP
      HealthDataAccess.READ, // SLEEP_AWAKE
      HealthDataAccess.READ, // SLEEP_AWAKE_IN_BED
      HealthDataAccess.READ, // SLEEP_DEEP
      HealthDataAccess.READ, // SLEEP_IN_BED
      HealthDataAccess.READ, // SLEEP_LIGHT
      HealthDataAccess.READ, // SLEEP_OUT_OF_BED
      HealthDataAccess.READ, // SLEEP_REM
      HealthDataAccess.READ, // SLEEP_SESSION
      HealthDataAccess.READ, // SLEEP_UNKNOWN
    ],
  ),
  HealthPermissionGroup(
    label: 'Питание',
    types: [HealthDataType.NUTRITION],
    permissions: [HealthDataAccess.READ], // read-only, фича вне скоупа
  ),
];

/// Все типы данных, которые приложение запрашивает у Health Connect.
///
/// WEIGHT и STEPS — `READ_WRITE` (ручной ввод пишется в Health Connect).
/// Остальные — `READ` (сон, питание).
///
/// Собирается из [kPermissionGroups] — группы всегда покрывают ровно этот
/// список (проверяется юнит-тестом).
List<HealthDataType> get kHealthDataTypes => [
  for (final group in kPermissionGroups) ...group.types,
];

/// Разрешения для [kHealthDataTypes] в том же порядке.
///
/// WEIGHT и STEPS — `READ_WRITE` (Фаза 2: запись ручного ввода в HC).
/// Сон и питание — `READ` (read-only, не трогаем).
List<HealthDataAccess> get kHealthDataAccess => [
  for (final group in kPermissionGroups) ...group.permissions,
];

/// Одна тихая проверка прав (`hasPermissions`, без системного диалога).
///
/// Отдельный тип для подмены в юнит-тестах — реальный `Health` требует
/// platform channel.
typedef HealthPermissionProbe =
    Future<bool?> Function(
      List<HealthDataType> types,
      List<HealthDataAccess> permissions,
    );

/// Тихо проверяет разрешения ОТДЕЛЬНЫМИ вызовами по каждому типу данных.
///
/// Для каждого типа из [kPermissionGroups] — свой вызов `hasPermissions`
/// (без системного диалога), значение каждого пермишена пишется в DebugLog
/// с тегом `perm`, по одной строке на пункт — сон разбит по стадиям
/// (10 строк; 2026-08-28: выяснилось, что для отдельных sleep-типов доступ
/// получить не удаётся — теперь видно, для каких именно):
///
/// ```
/// Вес (WEIGHT, READ_WRITE) → true
/// Шаги (STEPS, READ_WRITE) → false
/// Сон (SLEEP_ASLEEP, READ) → true
/// ... ещё 9 стадий сна ...
/// Питание (NUTRITION, READ) → true
/// ```
///
/// Возвращает map «пункт → значение» (13 записей), где `null` — статус
/// не определён (например, Health Connect недоступен). Исключение одного
/// типа не рушит остальные: логируется как error, пункт получает `null`.
///
/// [probe] переопределяет реальный вызов `hasPermissions` в тестах.
Future<Map<String, bool?>> checkPermissionsPerType(
  Health health, {
  HealthPermissionProbe? probe,
}) async {
  final checker =
      probe ??
      (types, permissions) =>
          health.hasPermissions(types, permissions: permissions);
  final results = <String, bool?>{};
  for (final group in kPermissionGroups) {
    for (var i = 0; i < group.types.length; i++) {
      final type = group.types[i];
      final access = group.permissions[i];
      final item = '${group.label} (${type.name}, ${access.name})';
      try {
        final granted = await checker([type], [access]);
        results[item] = granted;
        DebugLog.instance.log('perm', '$item → $granted');
      } catch (e) {
        // Отказ одного типа не должен рушить проверку остальных.
        results[item] = null;
        DebugLog.instance.error(
          'perm',
          '$item: hasPermissions бросил исключение — $e',
        );
      }
    }
  }
  return results;
}

/// Все ли метрики выданы: `true` только когда каждый результат строго `true`
/// (`null`/`false` считаются «не выдано» — та же семантика, что раньше
/// в `recheckPermissions`, где успехом считалось строго `== true`).
bool allGranted(Map<String, bool?> results) =>
    results.isNotEmpty && results.values.every((granted) => granted == true);

/// Запрашивает разрешения у Health Connect.
///
/// WEIGHT и STEPS запрашиваются с `READ_WRITE` (для записи ручного ввода),
/// остальные типы — с `READ`.
///
/// Сам запрос (`requestAuthorization`) остаётся ОДНИМ вызовом на все типы —
/// системный диалог Health Connect показывается один, UX онбординга не
/// меняется (решение пользователя 2026-08-28). Разделяются на отдельные
/// вызовы только тихие проверки: сразу после запроса
/// [checkPermissionsPerType] логирует значение каждого пермишена
/// (сон — по каждой стадии).
///
/// Возвращает `true` при успехе, `false` — если пользователь отказал
/// или Health Connect недоступен. В случае исключения (Health Connect
/// не установлен и т.п.) — пробрасывает наверх, не глушит.
///
/// Перед вызовом рекомендуется проверить [Health.hasPermissions],
/// т.к. повторный запрос при уже выданных правах может блокировать
/// (особенно на iOS, см. документацию пакета `health`).
///
/// [request] и [probe] переопределяют реальные вызовы пакета в тестах.
Future<bool> checkAndRequestPermissions(
  Health health, {
  Future<bool> Function(
    List<HealthDataType> types,
    List<HealthDataAccess> permissions,
  )?
  request,
  HealthPermissionProbe? probe,
}) async {
  final requester =
      request ??
      (types, permissions) =>
          health.requestAuthorization(types, permissions: permissions);
  try {
    final granted = await requester(kHealthDataTypes, kHealthDataAccess);
    DebugLog.instance.log(
      'perm',
      'requestAuthorization (${kHealthDataTypes.length} типов, один диалог) '
          '→ $granted',
    );
    // Детализация по каждому типу: отдельные тихие вызовы hasPermissions,
    // значение каждого пермишена — в журнал (тег perm).
    final perType = await checkPermissionsPerType(health, probe: probe);
    final allOk = allGranted(perType);
    final detail = perType.entries.map((e) => '${e.key}=${e.value}').join(', ');
    DebugLog.instance.log(
      'perm',
      'итог: ${allOk ? 'все пермишены выданы' : 'есть невыделенные'} ($detail)',
    );
    return granted;
  } catch (e) {
    DebugLog.instance.error('perm', 'requestAuthorization: исключение $e');
    rethrow;
  }
}
