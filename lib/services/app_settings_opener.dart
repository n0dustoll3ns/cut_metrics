import 'dart:io' show Platform;

import 'package:cut_metrics/services/debug_log.dart';
import 'package:flutter/services.dart';

/// Открывает системные настройки Android из Dart-кода.
///
/// Реализация — MethodChannel `cut_metrics/app_settings`, хендлер в
/// `MainActivity.kt`. Используется, когда разрешения Health Connect не выданы:
/// пользователь переходит на страницу приложения (Настройки → Приложения →
/// Cut Metrics → Разрешения) и выдаёт доступ вручную.
class AppSettingsOpener {
  AppSettingsOpener._();

  static const MethodChannel _channel = MethodChannel('cut_metrics/app_settings');

  /// Открывает страницу приложения в системных настройках.
  ///
  /// Возвращает `true` при успехе, `false` — если платформа не Android,
  /// канал не отвечает или системный экран не найден. Исключения не
  /// пробрасывает — кнопка просто «ничего не делает», ошибка идёт в DebugLog.
  static Future<bool> openAppSettings() async {
    if (!Platform.isAndroid) {
      DebugLog.instance.warn('perm', 'openAppSettings: не Android, пропускаем');
      return false;
    }
    try {
      final opened = await _channel.invokeMethod<bool>('openAppDetails');
      DebugLog.instance.log('perm', 'openAppSettings → $opened');
      return opened ?? false;
    } catch (e) {
      DebugLog.instance.error('perm', 'openAppSettings: $e');
      return false;
    }
  }
}
