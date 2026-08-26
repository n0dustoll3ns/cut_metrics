import 'package:cut_metrics/services/debug_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тесты журнала отладки (in-memory, кольцевой буфер, копирование).
void main() {
  late DebugLog debugLog;

  setUp(() {
    debugLog = DebugLog();
  });

  group('пустой журнал', () {
    test('entries пуст, copyAllText сообщает о пустоте', () {
      expect(debugLog.entries, isEmpty);
      expect(debugLog.copyAllText(), 'Журнал пуст');
    });
  });

  group('log/warn/error', () {
    test('log добавляет info-запись с тегом и сообщением', () {
      debugLog.log('repo', 'fetchRawData WEIGHT: 12 точек');

      expect(debugLog.entries, hasLength(1));
      final entry = debugLog.entries.single;
      expect(entry.tag, 'repo');
      expect(entry.level, DebugLogLevel.info);
      expect(entry.message, 'fetchRawData WEIGHT: 12 точек');
    });

    test('warn и error проставляют уровень', () {
      debugLog.warn('vm', 'permissions не выданы');
      debugLog.error('repo', 'исключение');

      expect(debugLog.entries[0].level, DebugLogLevel.warn);
      expect(debugLog.entries[1].level, DebugLogLevel.error);
    });

    test('записи хранятся от старых к новым', () {
      debugLog.log('app', 'первая');
      debugLog.log('vm', 'вторая');
      debugLog.log('repo', 'третья');

      expect(
        debugLog.entries.map((e) => e.message).toList(),
        ['первая', 'вторая', 'третья'],
      );
    });
  });

  group('кольцевой буфер', () {
    test('при переполнении вытесняются самые старые записи', () {
      const extra = 5;
      for (var i = 0; i < DebugLog.maxEntries + extra; i++) {
        debugLog.log('app', 'запись $i');
      }

      expect(debugLog.entries, hasLength(DebugLog.maxEntries));
      // Первые `extra` записей вытеснены — буфер начинается с записи `extra`.
      expect(debugLog.entries.first.message, 'запись $extra');
      expect(debugLog.entries.last.message, 'запись ${DebugLog.maxEntries + extra - 1}');
    });
  });

  group('clear', () {
    test('очищает записи и уведомляет слушателей', () {
      var notifications = 0;
      debugLog.addListener(() => notifications++);

      debugLog.log('app', 'до очистки');
      debugLog.clear();

      expect(debugLog.entries, isEmpty);
      expect(notifications, 2); // log + clear.
    });
  });

  group('notifyListeners', () {
    test('уведомляет на каждую запись', () {
      var notifications = 0;
      debugLog.addListener(() => notifications++);

      debugLog.log('app', '1');
      debugLog.warn('vm', '2');
      debugLog.error('repo', '3');

      expect(notifications, 3);
    });
  });

  group('copyAllText', () {
    test('формат: HH:mm:ss.mmm [тег] I сообщение, строки через \\n', () {
      debugLog.log('repo', 'fetchRawData WEIGHT: 12 точек');
      debugLog.error('vm', 'ошибка загрузки');

      final text = debugLog.copyAllText();
      final lines = text.split('\n');

      expect(lines, hasLength(2));
      expect(
        lines[0],
        matches(r'^\d{2}:\d{2}:\d{2}\.\d{3} \[repo\] I fetchRawData WEIGHT: 12 точек$'),
      );
      expect(
        lines[1],
        matches(r'^\d{2}:\d{2}:\d{2}\.\d{3} \[vm\] E ошибка загрузки$'),
      );
    });
  });

  group('formatTime', () {
    test('дополняет часы/минуты/секунды/мс до 2/2/2/3 знаков', () {
      final time = DateTime(2026, 8, 26, 5, 3, 2, 7);
      expect(DebugLog.formatTime(time), '05:03:02.007');
    });

    test('двузначные значения не дополняются', () {
      final time = DateTime(2026, 8, 26, 14, 30, 59, 123);
      expect(DebugLog.formatTime(time), '14:30:59.123');
    });
  });
}
