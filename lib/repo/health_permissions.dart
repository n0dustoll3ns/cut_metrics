import 'package:cut_metrics/services/debug_log.dart';
import 'package:health/health.dart';

/// Sleep-типы, поддерживаемые Health Connect на Android.
///
/// Все запрашиваются в `READ` — сон остаётся read-only (Фаза 2, секция 2).
///
/// ⚠️ `SLEEP_IN_BED` сюда НЕ включать — это iOS-only тип (HealthKit «время
/// в постели»). В пакете `health` 13.3.1/13.3.2 его нет ни в
/// `dataTypeKeysAndroid`, ни в нативном `mapToType`, поэтому `hasPermissions`
/// для него ВСЕГДА false (подтверждено на устройстве 2026-08-28), а пакетный
/// `requestAuthorization` с ним в списке молча возвращает false, не показывая
/// системный диалог. В Health Connect все стадии сна — одна запись
/// `SleepSessionRecord`, отдельного типа «в постели» не существует. Данные
/// сна не теряются: SleepAnalyzer работает через ASLEEP + DEEP/LIGHT/REM.
const List<HealthDataType> kSleepTypes = [
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_AWAKE_IN_BED,
  HealthDataType.SLEEP_DEEP,
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
/// Порядок групп задаёт порядок в [kHealthDataTypes]: ровно те же 12 типов
/// (13 → 12 после исключения iOS-only `SLEEP_IN_BED`, 2026-08-28).
/// Правило «все обязаны быть выданы» не меняется — разделяются только
/// тихие проверки и логи.
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
/// (9 строк; 2026-08-28: раздельная проверка выявила `SLEEP_IN_BED` —
/// iOS-only тип, для которого `hasPermissions` на Android всегда false;
/// исключён из [kSleepTypes]):
///
/// ```
/// Вес (WEIGHT, READ_WRITE) → true
/// Шаги (STEPS, READ_WRITE) → false
/// Сон (SLEEP_ASLEEP, READ) → true
/// ... ещё 8 стадий сна ...
/// Питание (NUTRITION, READ) → true
/// ```
///
/// Возвращает map «пункт → значение» (12 записей), где `null` — статус
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

/// Проверяет разрешения Health Connect и при необходимости запрашивает их.
///
/// WEIGHT и STEPS запрашиваются с `READ_WRITE` (для записи ручного ввода),
/// остальные типы — с `READ`.
///
/// Порядок работы (2026-08-28, фикс «поштучно все true, но load: permissions
/// не выданы»):
///
/// 1. Сначала тихая проверка [checkPermissionsPerType]. Если всё выдано —
///    `requestAuthorization` НЕ вызывается. Причина: нативная реализация
///    пакета `health` (13.3.1/13.3.2) при уже выданных правах всё равно
///    запускает системную активити и получает ПУСТОЙ granted-set (контракт
///    Health Connect возвращает только права, выданные в текущей сессии
///    запроса), а пустой набор трактует как отказ
///    (`HealthPlugin.kt`: `permissionGranted.isEmpty()` → `success(false)`).
///    Отсюда вечный баннер при полностью выданных правах.
/// 2. Если есть невыделенные типы — ОДИН пакетный `requestAuthorization`
///    на все типы (один системный диалог, UX онбординга не меняется —
///    решение пользователя 2026-08-28).
/// 3. Возвращается итог тихой проверки ПОСЛЕ запроса ([allGranted]), а не
///    сырой результат `requestAuthorization` — он ненадёжен (см. п. 1).
///
/// Возвращает `true`, если все пермишены выданы, `false` — если после
/// запроса что-то не выдано. В случае исключения (Health Connect не
/// установлен и т.п.) — пробрасывает наверх, не глушит.
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
    // Шаг 1. Тихая проверка: если всё уже выдано — запрос не нужен
    // (повторный requestAuthorization при выданных правах вернул бы false,
    // см. док-комментарий функции).
    final before = await checkPermissionsPerType(health, probe: probe);
    if (allGranted(before)) {
      DebugLog.instance.log('perm', 'все пермишены уже выданы — запрос не нужен');
      return true;
    }

    // Шаг 2. Есть невыделенные типы — один пакетный запрос (один диалог).
    final granted = await requester(kHealthDataTypes, kHealthDataAccess);
    DebugLog.instance.log(
      'perm',
      'requestAuthorization (${kHealthDataTypes.length} типов, один диалог) '
          '→ $granted',
    );

    // Шаг 3. Итог — по тихой проверке ПОСЛЕ запроса (не по `granted`):
    // результат `requestAuthorization` ненадёжен при уже выданных правах.
    // Значение каждого пермишена — в журнал (тег perm).
    final perType = await checkPermissionsPerType(health, probe: probe);
    final allOk = allGranted(perType);
    final detail = perType.entries.map((e) => '${e.key}=${e.value}').join(', ');
    DebugLog.instance.log(
      'perm',
      'итог: ${allOk ? 'все пермишены выданы' : 'есть невыделенные'} ($detail)',
    );
    return allOk;
  } catch (e) {
    DebugLog.instance.error('perm', 'requestAuthorization: исключение $e');
    rethrow;
  }
}
