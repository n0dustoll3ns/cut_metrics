import 'package:cut_metrics/domain/activity_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stepsToKcal', () {
    test('10 000 шагов при 80 кг ≈ 400 ккал', () {
      expect(stepsToKcal(10000, 80), closeTo(400, 1e-6));
    });

    test('0 шагов → 0 ккал', () {
      expect(stepsToKcal(0, 80), 0.0);
    });
  });

  group('trainingKcal (уровни 1–5)', () {
    test('уровень 1 — без добавки', () {
      expect(trainingKcal(ActivityLevel.level1, 80), 0.0);
    });

    test('уровень 3 при 80 кг ≈ +240 ккал', () {
      expect(trainingKcal(ActivityLevel.level3, 80), closeTo(240, 1e-6));
    });

    test('уровень 5 при 80 кг ≈ +480 ккал', () {
      expect(trainingKcal(ActivityLevel.level5, 80), closeTo(480, 1e-6));
    });
  });

  group('dailyCaloriesBurned', () {
    test('шаги + уровень: 10 000 шагов, 80 кг, уровень 3 ≈ 640 ккал', () {
      expect(
        dailyCaloriesBurned(steps: 10000, weightKg: 80, level: ActivityLevel.level3),
        closeTo(640, 1e-6),
      );
    });

    test('день без шагов — добавка уровня всё равно начисляется', () {
      expect(
        dailyCaloriesBurned(steps: 0, weightKg: 100, level: ActivityLevel.level2),
        closeTo(150, 1e-6),
      );
    });
  });

  group('ActivityLevel: номера и тексты', () {
    test('byNumber: 1..5 → level1..level5', () {
      for (var i = 1; i <= 5; i++) {
        expect(ActivityLevel.byNumber(i).number, i);
      }
    });

    test('byNumber: неверный номер → level1 (дефолт)', () {
      expect(ActivityLevel.byNumber(99), ActivityLevel.level1);
      expect(ActivityLevel.byNumber(0), ActivityLevel.level1);
    });

    test('у каждого уровня есть название и описание', () {
      for (final level in ActivityLevel.values) {
        expect(level.title, isNotEmpty);
        expect(level.description, isNotEmpty);
      }
    });
  });
}
