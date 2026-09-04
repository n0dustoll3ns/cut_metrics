/// Словарь имён источников данных Health Connect — Фаза 6, C.3.
///
/// Бедж и подэкран источников показывают человекочитаемое имя приложения,
/// а не package name. Правила fallback (по убыванию приоритета):
/// 1. Точное совпадение пакета в [kSourceNames] — готовое имя.
/// 2. Последний непустой сегмент package name (без точек).
/// 3. Пакет неизвестен/пуст — «Health Connect».
///
/// Словарь пополняется просто — добавить строку. Длинные имена обрезаются
/// до ~16 символов с «…» (см. [sourceBadgeLabel]).
///
/// Известные package → имя приложения.
const Map<String, String> kSourceNames = {
  'com.google.android.apps.fitness': 'Google Fit',
  'com.google.android.apps.healthdata': 'Health Connect',
  'com.sec.android.app.shealth': 'Samsung Health',
  'com.xiaomi.hm.health': 'Mi Fitness',
  'com.fitbit.fitbitmobile': 'Fitbit',
  'com.withings.wiscale2': 'Withings',
  'com.garmin.android.apps.connectmobile': 'Garmin Connect',
  'com.huawei.health': 'Huawei Health',
  'com.polar.polarflow': 'Polar Flow',
};

/// Человекочитаемое имя источника по пакету (без обрезки).
String displaySourceName(String package) {
  final known = kSourceNames[package];
  if (known != null) return known;

  final segments = package.split('.').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return 'Health Connect';
  return segments.last;
}

/// Обрезает имя до [maxChars] символов с «…» (бедж — одна строка).
String truncateSourceName(String name, {int maxChars = 16}) {
  if (name.length <= maxChars) return name;
  return '${name.substring(0, maxChars)}…';
}

/// Текст беджа источника: «Из Google Fit» / «Из Health Connect» (fallback).
String sourceBadgeLabel(String? package) {
  if (package == null || package.isEmpty) return 'Из Health Connect';
  return 'Из ${truncateSourceName(displaySourceName(package))}';
}
