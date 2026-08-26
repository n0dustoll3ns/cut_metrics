import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Уровень записи журнала отладки.
enum DebugLogLevel {
  /// Обычное событие (вызов репозитория, стадия загрузки).
  info,

  /// Подозрительное, но не фатальное (отказ в permissions и т.п.).
  warn,

  /// Ошибка (исключение, неудачная операция).
  error,
}

/// Одна запись журнала отладки.
///
/// Время хранится как [DateTime] — в строку форматируется лениво на экране
/// ([DebugLog.formatTime]), чтобы не плодить строковые аллокации на каждый вызов.
class DebugLogEntry {
  final DateTime time;
  final String tag;
  final DebugLogLevel level;
  final String message;

  const DebugLogEntry({
    required this.time,
    required this.tag,
    required this.level,
    required this.message,
  });
}

/// In-memory журнал отладки — «консоль» внутри приложения для release-сборок.
///
/// Мотивация: в release APK нет `flutter logs`, а четыре техриска Фаз 2/4
/// (см. `techContext.md`) нужно проверять на реальном устройстве. Журнал
/// собирает сообщения из кода в кольцевой буфер, экран `DebugLogScreen`
/// показывает их и копирует в буфер обмена.
///
/// Характеристики (согласовано с пользователем, 2026-08-26):
/// - **In-memory, только за сессию** — не персистентно, при перезапуске пусто
///   (осознанно: без SharedPreferences/файлов; логи холодного старта `load()`
///   видны сразу после запуска).
/// - Кольцевой буфер [maxEntries] записей (`ListQueue`), старые вытесняются.
/// - Работает **всегда, включая release** — вызовы не обёрнуты в `kDebugMode`.
/// - Синглтон [instance] — один журнал на приложение; UI подписывается через
///   `ListenableBuilder` (ChangeNotifier).
///
/// Теги-пользователи журнала:
/// - `app` — `main.dart` (старт приложения, режим сборки);
/// - `vm` — `DashboardViewModel` (load/submit/cancel, ошибки);
/// - `repo` — `HealthRepositoryImpl` (чтение/запись/удаление HC, sourceId);
/// - `perm` — `health_permissions.dart` (результат requestAuthorization).
class DebugLog extends ChangeNotifier {
  /// Публичный конструктор — для юнит-тестов (свежий экземпляр на тест).
  /// В приложении используется синглтон [instance].
  DebugLog();

  static final DebugLog instance = DebugLog();

  /// Вместимость кольцевого буфера: при переполнении старые записи удаляются.
  ///
  /// 1000 записей покрывает типичную сессию (один `load()` ≈ 10–15 записей).
  static const int maxEntries = 1000;

  final ListQueue<DebugLogEntry> _entries = ListQueue(maxEntries);

  /// Записи от старых к новым (неизменяемая копия для чтения).
  List<DebugLogEntry> get entries => List.unmodifiable(_entries);

  /// Добавляет запись уровня [DebugLogLevel.info].
  void log(String tag, String message) =>
      _add(tag, DebugLogLevel.info, message);

  /// Добавляет запись уровня [DebugLogLevel.warn].
  void warn(String tag, String message) =>
      _add(tag, DebugLogLevel.warn, message);

  /// Добавляет запись уровня [DebugLogLevel.error].
  void error(String tag, String message) =>
      _add(tag, DebugLogLevel.error, message);

  void _add(String tag, DebugLogLevel level, String message) {
    _entries.add(DebugLogEntry(
      time: DateTime.now(),
      tag: tag,
      level: level,
      message: message,
    ));
    if (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  /// Очищает журнал.
  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Все записи одним текстом (старые сверху, новые внизу) — для «Копировать всё».
  String copyAllText() {
    final lines = _entries
        .map((e) =>
            '${formatTime(e.time)} [${e.tag}] ${_levelLetter(e.level)} ${e.message}')
        .toList();
    return lines.isEmpty ? 'Журнал пуст' : lines.join('\n');
  }

  /// `HH:mm:ss.mmm` — локальное время записи.
  static String formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$ms';
  }

  static String _levelLetter(DebugLogLevel level) => switch (level) {
        DebugLogLevel.info => 'I',
        DebugLogLevel.warn => 'W',
        DebugLogLevel.error => 'E',
      };
}
