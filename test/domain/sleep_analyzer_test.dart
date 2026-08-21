import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/sleep_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Хелпер: интервал сна как HealthDataPoint.
HealthDataPoint interval(DateTime from, DateTime to, HealthDataType type) {
  return HealthDataPoint(
    sourceName: 'test.tracker',
    uuid: '',
    sourceDeviceId: '',
    sourceId: 'test.tracker',
    sourcePlatform: HealthPlatformType.googleHealthConnect,
    value: NumericHealthValue(numericValue: to.difference(from).inMinutes),
    dateFrom: from,
    dateTo: to,
    type: type,
    unit: HealthDataUnit.MINUTE,
    recordingMethod: RecordingMethod.automatic,
  );
}

DateKey dk(int y, int m, int d) => DateKey(DateTime(y, m, d));

void main() {
  final rangeStart = DateTime(2026, 7, 1);
  final rangeEnd = DateTime(2026, 7, 31);

  SleepAnalyzer analyzer() => SleepAnalyzer();

  group('стадии сна (перенос из old_proj)', () {
    test('DEEP + LIGHT + REM суммируются в total', () {
      final result = analyzer().analyze(
        rawPoints: [
          interval(DateTime(2026, 7, 23, 23), DateTime(2026, 7, 24), HealthDataType.SLEEP_DEEP),
          interval(DateTime(2026, 7, 24), DateTime(2026, 7, 24, 6), HealthDataType.SLEEP_LIGHT),
          interval(DateTime(2026, 7, 24, 6), DateTime(2026, 7, 24, 7), HealthDataType.SLEEP_REM),
        ],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );

      final day = result[dk(2026, 7, 24)]!;
      expect(day.deep, closeTo(1, 1e-9));
      expect(day.light, closeTo(6, 1e-9));
      expect(day.rem, closeTo(1, 1e-9));
      expect(day.total, closeTo(8, 1e-9));
    });

    test('пересекающиеся стадии одного слоя обрезаются (overwrite)', () {
      final result = analyzer().analyze(
        rawPoints: [
          interval(DateTime(2026, 7, 23, 23), DateTime(2026, 7, 24, 2), HealthDataType.SLEEP_LIGHT),
          interval(DateTime(2026, 7, 24, 1, 30), DateTime(2026, 7, 24, 3), HealthDataType.SLEEP_LIGHT),
        ],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      // 23:00→01:30 (2.5ч) + 01:30→03:00 (1.5ч) = 4ч.
      expect(result[dk(2026, 7, 24)]!.total, closeTo(4, 1e-9));
    });
  });

  group('SLEEP_ASLEEP приоритет (С2)', () {
    test('есть ASLEEP за ночь → total = ASLEEP, стадии игнорируются', () {
      final result = analyzer().analyze(
        rawPoints: [
          interval(DateTime(2026, 7, 23, 23), DateTime(2026, 7, 24), HealthDataType.SLEEP_DEEP),
          interval(DateTime(2026, 7, 24), DateTime(2026, 7, 24, 6), HealthDataType.SLEEP_LIGHT),
          interval(DateTime(2026, 7, 23, 23), DateTime(2026, 7, 24, 7, 30), HealthDataType.SLEEP_ASLEEP),
        ],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      final day = result[dk(2026, 7, 24)]!;
      expect(day.asleep, closeTo(8.5, 1e-9));
      expect(day.total, closeTo(8.5, 1e-9));
    });

    test('только ASLEEP (трекер без стадий) → total = ASLEEP', () {
      final result = analyzer().analyze(
        rawPoints: [
          interval(DateTime(2026, 7, 23, 23), DateTime(2026, 7, 24, 7), HealthDataType.SLEEP_ASLEEP),
        ],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      expect(result[dk(2026, 7, 24)]!.total, closeTo(8, 1e-9));
    });
  });

  group('правило дня сна (С3)', () {
    test('интервал после 12:00 относится к следующему дню', () {
      final result = analyzer().analyze(
        rawPoints: [
          interval(DateTime(2026, 7, 23, 23), DateTime(2026, 7, 24, 7), HealthDataType.SLEEP_ASLEEP),
        ],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      expect(result.containsKey(dk(2026, 7, 23)), isFalse);
      expect(result.containsKey(dk(2026, 7, 24)), isTrue);
    });

    test('утренний интервал до 12:00 остаётся в своём дне сна', () {
      final result = analyzer().analyze(
        rawPoints: [
          interval(DateTime(2026, 7, 24, 10), DateTime(2026, 7, 24, 11), HealthDataType.SLEEP_LIGHT),
        ],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      expect(result.containsKey(dk(2026, 7, 24)), isTrue);
    });
  });

  group('пустые ночи (С4)', () {
    test('ночи без данных не попадают в результат', () {
      final result = analyzer().analyze(
        rawPoints: [
          interval(DateTime(2026, 7, 22, 23), DateTime(2026, 7, 23, 7), HealthDataType.SLEEP_ASLEEP),
        ],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      expect(result.length, 1);
      expect(result.containsKey(dk(2026, 7, 23)), isTrue);
    });

    test('ночь за границей диапазона отбрасывается', () {
      final result = analyzer().analyze(
        rawPoints: [
          interval(DateTime(2026, 7, 22, 23), DateTime(2026, 7, 23, 7), HealthDataType.SLEEP_ASLEEP),
          interval(DateTime(2026, 7, 25, 23), DateTime(2026, 7, 26, 7), HealthDataType.SLEEP_ASLEEP),
        ],
        rangeStart: DateTime(2026, 7, 24),
        rangeEnd: DateTime(2026, 7, 31),
      );
      expect(result.length, 1);
      expect(result.containsKey(dk(2026, 7, 23)), isFalse);
      expect(result.containsKey(dk(2026, 7, 26)), isTrue);
    });
  });
}
