import 'package:cut_metrics/repo/health_permissions.dart';
import 'package:cut_metrics/services/debug_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Тесты раздельной проверки разрешений по каждому типу (2026-08-28).
///
/// Реальные вызовы `Health` требуют platform channel, поэтому в тестах
/// подменяются injectable-параметрами `probe` / `request`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kPermissionGroups', () {
    test('ровно покрывают kHealthDataTypes (состав и порядок)', () {
      final flattened = [for (final group in kPermissionGroups) ...group.types];
      expect(flattened, kHealthDataTypes);
    });

    test('длины types и permissions совпадают в каждой группе', () {
      for (final group in kPermissionGroups) {
        expect(
          group.permissions.length,
          group.types.length,
          reason: group.label,
        );
      }
    });

    test('вес и шаги — READ_WRITE, сон и питание — READ', () {
      final byLabel = {
        for (final group in kPermissionGroups) group.label: group,
      };
      expect(
        byLabel['Вес']!.permissions,
        everyElement(HealthDataAccess.READ_WRITE),
      );
      expect(
        byLabel['Шаги']!.permissions,
        everyElement(HealthDataAccess.READ_WRITE),
      );
      expect(byLabel['Сон']!.permissions, everyElement(HealthDataAccess.READ));
      expect(byLabel['Питание']!.permissions.single, HealthDataAccess.READ);
    });
  });

  group('checkPermissionsPerType', () {
    test(
      'отдельный вызов и строка лога на каждый тип (сон — по стадиям)',
      () async {
        DebugLog.instance.clear();
        var calls = 0;
        final result = await checkPermissionsPerType(
          Health(),
          probe: (types, permissions) async {
            calls++;
            return types.first != HealthDataType.STEPS; // шаги не выданы
          },
        );

        // 12 типов: вес + шаги + 9 стадий сна + питание.
        expect(calls, kHealthDataTypes.length);
        expect(result, hasLength(kHealthDataTypes.length));
        expect(result['Вес (WEIGHT, READ_WRITE)'], isTrue);
        expect(result['Шаги (STEPS, READ_WRITE)'], isFalse);
        expect(result['Сон (SLEEP_ASLEEP, READ)'], isTrue);
        expect(result['Питание (NUTRITION, READ)'], isTrue);
        // Все 9 стадий сна — отдельными записями.
        expect(
          result.keys.where((k) => k.startsWith('Сон (SLEEP_')),
          hasLength(kSleepTypes.length),
        );

        final permLines = DebugLog.instance.entries
            .where((e) => e.tag == 'perm' && e.level == DebugLogLevel.info)
            .map((e) => e.message)
            .toList();
        expect(permLines.length, kHealthDataTypes.length);
        expect(
          permLines.any((m) => m.contains('Вес (WEIGHT') && m.contains('true')),
          isTrue,
        );
        expect(
          permLines.any(
            (m) => m.contains('Шаги (STEPS') && m.contains('false'),
          ),
          isTrue,
        );
        // SLEEP_IN_BED исключён (iOS-only) — в логах его быть не должно.
        expect(permLines.any((m) => m.contains('SLEEP_IN_BED')), isFalse);
      },
    );

    test('исключение одного типа логируется как error, пункт null', () async {
      DebugLog.instance.clear();
      final result = await checkPermissionsPerType(
        Health(),
        probe: (types, permissions) async {
          if (types.first == HealthDataType.SLEEP_ASLEEP) {
            throw Exception('Health Connect недоступен');
          }
          return true;
        },
      );

      expect(result['Сон (SLEEP_ASLEEP, READ)'], isNull);
      expect(result['Сон (SLEEP_DEEP, READ)'], isTrue);
      expect(result['Вес (WEIGHT, READ_WRITE)'], isTrue);

      final errors = DebugLog.instance.entries
          .where((e) => e.level == DebugLogLevel.error && e.tag == 'perm')
          .toList();
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('SLEEP_ASLEEP'));
    });
  });

  group('регрессия: Android-поддержка типов (2026-08-28)', () {
    test('каждый запрашиваемый тип есть в dataTypeKeysAndroid пакета health '
        '(SLEEP_IN_BED — iOS-only, исключён из kSleepTypes)', () {
      // Тип вне dataTypeKeysAndroid на Android не работает: hasPermissions
      // всегда false, requestAuthorization молча фейлится без диалога
      // (пакет health 13.3.1/13.3.2, нативный mapToType).
      for (final group in kPermissionGroups) {
        for (final type in group.types) {
          expect(
            dataTypeKeysAndroid.contains(type),
            isTrue,
            reason: '${group.label}: $type не поддерживается на Android',
          );
        }
      }
      expect(kSleepTypes, isNot(contains(HealthDataType.SLEEP_IN_BED)));
    });
  });

  group('allGranted', () {
    test('true только когда все значения строго true', () {
      expect(allGranted({'a': true, 'b': true}), isTrue);
      expect(allGranted({'a': true, 'b': false}), isFalse);
      expect(allGranted({'a': true, 'b': null}), isFalse);
      expect(allGranted(<String, bool?>{}), isFalse);
    });
  });

  group('checkAndRequestPermissions', () {
    test('один requestAuthorization + лог по каждому типу', () async {
      DebugLog.instance.clear();
      var requestCalls = 0;
      var probeCalls = 0;

      final granted = await checkAndRequestPermissions(
        Health(),
        request: (types, permissions) async {
          requestCalls++;
          return false; // пользователь отказал
        },
        probe: (types, permissions) async {
          probeCalls++;
          // Не выданы шаги и питание — видно, какой именно тип провалился.
          return types.first != HealthDataType.STEPS &&
              !types.contains(HealthDataType.NUTRITION);
        },
      );

      expect(granted, isFalse);
      expect(requestCalls, 1); // запрос — один вызов на все типы
      expect(probeCalls, kHealthDataTypes.length); // проверка — по типам

      final permLines = DebugLog.instance.entries
          .where((e) => e.tag == 'perm')
          .map((e) => e.message)
          .toList();
      expect(
        permLines.any((m) => m.startsWith('requestAuthorization')),
        isTrue,
      );
      for (final group in kPermissionGroups) {
        expect(
          permLines.any((m) => m.contains(group.label)),
          isTrue,
          reason: 'нет строки для ${group.label}',
        );
      }
      expect(
        permLines.any((m) => m.contains('SLEEP_IN_BED')),
        isFalse, // iOS-only тип исключён из запроса (2026-08-28)
      );
      expect(
        permLines.any(
          (m) =>
              m.contains('итог') &&
              m.contains('Шаги (STEPS, READ_WRITE)=false'),
        ),
        isTrue,
      );
    });
  });
}
