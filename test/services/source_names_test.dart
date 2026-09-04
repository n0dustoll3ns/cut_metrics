import 'package:cut_metrics/services/source_names.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тесты словаря имён источников (Фаза 6, C.3): известные пакеты, fallback
/// по последнему сегменту, обрезка беджа.
void main() {
  test('известный пакет → имя из словаря', () {
    expect(
      displaySourceName('com.google.android.apps.fitness'),
      'Google Fit',
    );
    expect(displaySourceName('com.sec.android.app.shealth'), 'Samsung Health');
    expect(displaySourceName('com.xiaomi.hm.health'), 'Mi Fitness');
  });

  test('неизвестный пакет → последний сегмент', () {
    expect(displaySourceName('com.some.unknown.tracker'), 'tracker');
  });

  test('пустой/битый пакет → Health Connect', () {
    expect(displaySourceName(''), 'Health Connect');
    expect(displaySourceName('...'), 'Health Connect');
  });

  test('бедж: «Из …» + обрезка ~16 символов', () {
    expect(sourceBadgeLabel('com.google.android.apps.fitness'), 'Из Google Fit');
    expect(sourceBadgeLabel(null), 'Из Health Connect');
    expect(sourceBadgeLabel(''), 'Из Health Connect');
    // Длинное имя обрезается с «…»:
    final label = sourceBadgeLabel('com.some.unknown.verylongtrackername');
    expect(label.length, lessThanOrEqualTo('Из '.length + 17));
    expect(label.endsWith('…'), isTrue);
  });

  test('короткое имя не обрезается', () {
    expect(truncateSourceName('Google Fit'), 'Google Fit');
    expect(truncateSourceName('Samsung Health'), 'Samsung Health'); // 14 симв.
  });
}
