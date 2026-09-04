import 'package:cut_metrics/services/settings_service.dart';
import 'package:flutter/material.dart';

/// Контроллер режима темы — Фаза 6, D.2.
///
/// Три режима: системный / светлый / тёмный. Дефолт — системный («Тёмная
/// включается вместе с системной»). Персист через [SettingsService]
/// (ключ `theme_mode`), `MaterialApp` слушает через provider.
class ThemeController extends ChangeNotifier {
  final SettingsService? _settings;

  ThemeController({SettingsService? settingsService}) : _settings = settingsService;

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Загружает сохранённый режим (вызывается на старте, до первого кадра —
  /// иначе мелькает системная тема при сохранённой светлой/тёмной).
  Future<void> load() async {
    if (_settings == null) return;
    _mode = _parseMode(await _settings.loadThemeModeName());
    notifyListeners();
  }

  /// Устанавливает режим и персистит. Мгновенное применение, без «Сохранить».
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await _settings?.saveThemeModeName(mode.name);
    notifyListeners();
  }

  static ThemeMode _parseMode(String name) => switch (name) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
