import 'package:cut_metrics/repo/health_permissions.dart';
import 'package:cut_metrics/services/debug_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Тесты раздельной проверки разрешений по метрикам (2026-08-28).
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

  group('checkPermissionsByMetric', () {
    test('отдельный вызов и строка лога на каждую метрику', () async {
      DebugLog.instance.clear();
      var calls = 0;
      final result = await checkPermissionsByMetric(
        Health(),
        probe: (types, permissions) async {
          calls++;
          return types.first != HealthDataType.STEPS; // шаги не выданы
        },
      );

      expect(calls, kPermissionGroups.length);
      expect(result['Вес'], isTrue);
      expect(result['Шаги'], isFalse);
      expect(result['Сон'], isTrue);
      expect(result['Питание'], isTrue);

      final permLines = DebugLog.instance.entries
          .where((e) => e.tag == 'perm' && e.level == DebugLogLevel.info)
          .map((e) => e.message)
          .toList();
      expect(permLines.length, kPermissionGroups.length);
      expect(
        permLines.any((m) => m.contains('Вес') && m.contains('true')),
        isTrue,
      );
      expect(
        permLines.any((m) => m.contains('Шаги') && m.contains('false')),
        isTrue,
      );
    });

    test('исключение группы логируется как error, метрика null', () async {
      DebugLog.instance.clear();
      final result = await checkPermissionsByMetric(
        Health(),
        probe: (types, permissions) async {
          if (types.contains(HealthDataType.SLEEP_ASLEEP)) {
            throw Exception('Health Connect недоступен');
          }
          return true;
        },
      );

      expect(result['Сон'], isNull);
      expect(result['Вес'], isTrue);
      expect(result['Шаги'], isTrue);
      expect(result['Питание'], isTrue);

      final errors = DebugLog.instance.entries
          .where((e) => e.level == DebugLogLevel.error && e.tag == 'perm')
          .toList();
      expect(errors, hasLength(1));
      expect(errors.single.message, contains('Сон'));
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
    test('один requestAuthorization + лог по каждой метрике', () async {
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
          // Не выданы шаги и питание — видно, какая именно метрика провалилась.
          return types.first != HealthDataType.STEPS &&
              !types.contains(HealthDataType.NUTRITION);
        },
      );

      expect(granted, isFalse);
      expect(requestCalls, 1); // запрос — один вызов на все типы
      expect(probeCalls, kPermissionGroups.length); // проверка — по метрикам

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
        permLines.any((m) => m.contains('итог') && m.contains('Шаги=false')),
        isTrue,
      );
    });
  });
}
