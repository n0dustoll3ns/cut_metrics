import 'package:cut_metrics/services/settings_service.dart';
import 'package:cut_metrics/services/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тесты ThemeController (Фаза 6, D.2): дефолт system, сеттер персистит.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('дефолт — системная тема', () {
    final controller = ThemeController();
    expect(controller.mode, ThemeMode.system);
  });

  test('load поднимает сохранённый режим (dark)', () async {
    final settings = SettingsService();
    await settings.saveThemeModeName('dark');

    final controller = ThemeController(settingsService: settings);
    await controller.load();

    expect(controller.mode, ThemeMode.dark);
  });

  test('setMode меняет режим и персистит', () async {
    final settings = SettingsService();
    final controller = ThemeController(settingsService: settings);

    await controller.setMode(ThemeMode.dark);
    expect(controller.mode, ThemeMode.dark);
    expect(await settings.loadThemeModeName(), 'dark');

    await controller.setMode(ThemeMode.light);
    expect(controller.mode, ThemeMode.light);
    expect(await settings.loadThemeModeName(), 'light');
  });

  test('неизвестное имя режима → system (fallback)', () async {
    final settings = SettingsService();
    await settings.saveThemeModeName('какой-то мусор');

    final controller = ThemeController(settingsService: settings);
    await controller.load();

    expect(controller.mode, ThemeMode.system);
  });

  test('без SettingsService сеттер не падает (тесты без персиста)', () async {
    final controller = ThemeController();
    await controller.setMode(ThemeMode.dark);
    expect(controller.mode, ThemeMode.dark);
  });
}
