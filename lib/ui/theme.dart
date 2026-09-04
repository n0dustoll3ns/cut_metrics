import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Цветовые роли дизайн-системы Cut Metrics — ThemeExtension (Фаза 6, D.1).
///
/// Значения — точно из `docs/design-system.html` (секция «Тёмная тема»):
/// светлая — базовая, тёмная — производная «приборная» (фон #101214,
/// карточки светлее фона, Deep Ink инвертируется в светлый текст, брендовые
/// signal/steady/alert осветлены до AA, tint-подложки затемнены).
/// Новых ролей относительно Фаз 3–5 нет — добавлен только `onSignal`
/// (текст на primary-кнопке; в тёмной теме инвертируется).
///
/// Доступ из UI — `context.cmColors` (extension ниже). Статических ссылок на
/// цвета не использовать: одна и та же роль меняет значение в зависимости
/// от яркости темы.
@immutable
class CMThemeColors extends ThemeExtension<CMThemeColors> {
  /// Фон/канва.
  final Color bg;

  /// Карточки.
  final Color surface0;

  /// = bg (заливки внутри карточек).
  final Color surface1;

  /// Ховеры, заполнения, беджи внешних источников.
  final Color surface2;

  /// Линии, сетка графика.
  final Color outline;

  /// Рамки полей ввода.
  final Color outlineStrong;

  /// Основной текст (Deep Ink / инверсия).
  final Color ink;

  /// Второстепенный текст.
  final Color inkMuted;

  /// Сырые точки, подписи осей.
  final Color noise;

  /// Акцент, тренд, CTA (Signal Cobalt / осветлённый).
  final Color signal;

  final Color signalHover;
  final Color signalPress;

  /// Подложка ручного ввода.
  final Color signalTint;

  /// Текст/иконки на primary-кнопке (в тёмной — тёмный на светлой кнопке).
  final Color onSignal;

  /// Статус «в темпе» (Steady Green / осветлённый).
  final Color steady;
  final Color steadyTint;
  final Color steadyBorder;

  /// Ошибки, отклонения (Alert Rust / осветлённый).
  final Color alert;
  final Color alertTint;
  final Color alertBorder;

  /// Полупрозрачные точки графика (noise @55%).
  final Color noiseLight;

  const CMThemeColors({
    required this.bg,
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.outline,
    required this.outlineStrong,
    required this.ink,
    required this.inkMuted,
    required this.noise,
    required this.signal,
    required this.signalHover,
    required this.signalPress,
    required this.signalTint,
    required this.onSignal,
    required this.steady,
    required this.steadyTint,
    required this.steadyBorder,
    required this.alert,
    required this.alertTint,
    required this.alertBorder,
    required this.noiseLight,
  });

  /// Светлая тема — базовая (значения Фаз 3–5).
  static const CMThemeColors light = CMThemeColors(
    bg: Color(0xFFF3F5F6),
    surface0: Color(0xFFFFFFFF),
    surface1: Color(0xFFF3F5F6),
    surface2: Color(0xFFE7EAEC),
    outline: Color(0xFFD7DBDE),
    outlineStrong: Color(0xFFC2C7CC),
    ink: Color(0xFF14171A),
    inkMuted: Color(0xFF4B5259),
    noise: Color(0xFF9CA3AF),
    signal: Color(0xFF2A5DB0),
    signalHover: Color(0xFF234C8D),
    signalPress: Color(0xFF1D3F73),
    signalTint: Color(0xFFE7EEF8),
    onSignal: Color(0xFFFFFFFF),
    steady: Color(0xFF1F9D6C),
    steadyTint: Color(0xFFE4F5EE),
    steadyBorder: Color(0xFFBEE3D2),
    alert: Color(0xFFB23A2E),
    alertTint: Color(0xFFFBEAE8),
    alertBorder: Color(0xFFEFC5BF),
    noiseLight: Color(0x559CA3AF),
  );

  /// Тёмная тема — «приборная» (маппинг из `docs/design-system.html`, §06).
  static const CMThemeColors dark = CMThemeColors(
    bg: Color(0xFF101214),
    surface0: Color(0xFF191C1F),
    surface1: Color(0xFF101214),
    surface2: Color(0xFF23272C),
    outline: Color(0xFF2B3036),
    outlineStrong: Color(0xFF3A4046),
    ink: Color(0xFFE8EAEC),
    inkMuted: Color(0xFF9AA1A9),
    noise: Color(0xFF6E757D),
    signal: Color(0xFF7EA4E6),
    signalHover: Color(0xFF8FB2EB),
    signalPress: Color(0xFF6F97DE),
    signalTint: Color(0xFF1C2836),
    onSignal: Color(0xFF101214),
    steady: Color(0xFF52C695),
    steadyTint: Color(0xFF142E25),
    steadyBorder: Color(0xFF24584A),
    alert: Color(0xFFE57F72),
    alertTint: Color(0xFF38211E),
    alertBorder: Color(0xFF6E372F),
    noiseLight: Color(0x556E757D),
  );

  @override
  CMThemeColors copyWith({
    Color? bg,
    Color? surface0,
    Color? surface1,
    Color? surface2,
    Color? outline,
    Color? outlineStrong,
    Color? ink,
    Color? inkMuted,
    Color? noise,
    Color? signal,
    Color? signalHover,
    Color? signalPress,
    Color? signalTint,
    Color? onSignal,
    Color? steady,
    Color? steadyTint,
    Color? steadyBorder,
    Color? alert,
    Color? alertTint,
    Color? alertBorder,
    Color? noiseLight,
  }) {
    return CMThemeColors(
      bg: bg ?? this.bg,
      surface0: surface0 ?? this.surface0,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      outline: outline ?? this.outline,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      noise: noise ?? this.noise,
      signal: signal ?? this.signal,
      signalHover: signalHover ?? this.signalHover,
      signalPress: signalPress ?? this.signalPress,
      signalTint: signalTint ?? this.signalTint,
      onSignal: onSignal ?? this.onSignal,
      steady: steady ?? this.steady,
      steadyTint: steadyTint ?? this.steadyTint,
      steadyBorder: steadyBorder ?? this.steadyBorder,
      alert: alert ?? this.alert,
      alertTint: alertTint ?? this.alertTint,
      alertBorder: alertBorder ?? this.alertBorder,
      noiseLight: noiseLight ?? this.noiseLight,
    );
  }

  @override
  CMThemeColors lerp(ThemeExtension<CMThemeColors>? other, double t) {
    if (other is! CMThemeColors) return this;
    return CMThemeColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface0: Color.lerp(surface0, other.surface0, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      noise: Color.lerp(noise, other.noise, t)!,
      signal: Color.lerp(signal, other.signal, t)!,
      signalHover: Color.lerp(signalHover, other.signalHover, t)!,
      signalPress: Color.lerp(signalPress, other.signalPress, t)!,
      signalTint: Color.lerp(signalTint, other.signalTint, t)!,
      onSignal: Color.lerp(onSignal, other.onSignal, t)!,
      steady: Color.lerp(steady, other.steady, t)!,
      steadyTint: Color.lerp(steadyTint, other.steadyTint, t)!,
      steadyBorder: Color.lerp(steadyBorder, other.steadyBorder, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      alertTint: Color.lerp(alertTint, other.alertTint, t)!,
      alertBorder: Color.lerp(alertBorder, other.alertBorder, t)!,
      noiseLight: Color.lerp(noiseLight, other.noiseLight, t)!,
    );
  }
}

/// Доступ к ролям темы из BuildContext: `context.cmColors.ink`.
extension CMColorsContext on BuildContext {
  CMThemeColors get cmColors =>
      Theme.of(this).extension<CMThemeColors>() ?? CMThemeColors.light;
}

/// Радиусы — сдержанные, "инструментальные" (не мягкие/игривые).
class CMRadius {
  CMRadius._();

  static const sm = 6.0; // чипы, бейджи
  static const md = 10.0; // кнопки, поля
  static const lg = 16.0; // карточки
  static const xl = 20.0; // крупные модалки
}

/// Отступы — 8pt grid.
class CMSpacing {
  CMSpacing._();

  static const sp1 = 4.0;
  static const sp2 = 8.0;
  static const sp3 = 12.0;
  static const sp4 = 16.0;
  static const sp6 = 24.0;
  static const sp8 = 32.0;
  static const sp12 = 48.0;
  static const sp16 = 64.0;
}

/// Шрифты дизайн-системы.
///
/// - Space Grotesk — числа (tabular-nums), главный герой интерфейса.
/// - Inter — текст (заголовки, body).
/// - Space Mono — подписи, даты, единицы (uppercase, моноширинный).
///
/// `color` — обязательный параметр: дефолт из статических цветов убран
/// (Фаза 6, D.1) — вызывающий код берёт роль из `context.cmColors`, иначе
/// в тёмной теме молча получался бы тёмный текст на тёмном фоне.
class CMFonts {
  CMFonts._();

  /// Числа: Space Grotesk, табличные цифры.
  static TextStyle metric({
    double size = 26,
    FontWeight weight = FontWeight.w500,
    required Color color,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: -0.01,
        height: 1.0,
      );

  /// Заголовок: Inter 600.
  static TextStyle heading({
    double size = 19,
    required Color color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Body: Inter 400.
  static TextStyle body({
    double size = 16,
    required Color color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  /// Label/бейдж: Inter 600 — статус-беджи, метки (`.badge` дизайн-системы).
  static TextStyle label({
    double size = 13,
    required Color color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Caption/моно: Space Mono uppercase — даты, единицы, подписи.
  static TextStyle caption({
    double size = 12,
    required Color color,
  }) =>
      GoogleFonts.spaceMono(
        fontSize: size,
        color: color,
        letterSpacing: 0.05,
      );
}

/// Тема приложения — Material 3, настроенная на токены дизайн-системы.
///
/// Фаза 6, D.1: `MaterialApp.theme` = `cmTheme(Brightness.light)`,
/// `MaterialApp.darkTheme` = `cmTheme(Brightness.dark)` — один конструктор
/// на обе темы, роли приходят из [CMThemeColors]. AppBar, NavigationBar,
/// снекбары и карточки настроены здесь — экраны не хардкодят цвета.
ThemeData cmTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? CMThemeColors.dark : CMThemeColors.light;
  final isDark = brightness == Brightness.dark;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    colorScheme: (isDark ? ColorScheme.dark : ColorScheme.light)(
      primary: c.signal,
      onPrimary: c.onSignal,
      secondary: c.signal,
      surface: c.surface0,
      onSurface: c.ink,
      error: c.alert,
      outline: c.outline,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface0,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface0,
      indicatorColor: c.signalTint,
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: c.inkMuted)),
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? c.surface2 : c.ink,
      contentTextStyle: GoogleFonts.inter(
        fontSize: 14,
        color: isDark ? c.ink : CMThemeColors.light.bg,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.outline, thickness: 1),
    cardTheme: CardThemeData(
      color: c.surface0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CMRadius.lg),
        side: BorderSide(color: c.outline),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface0,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: CMSpacing.sp4,
        vertical: CMSpacing.sp3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CMRadius.md),
        borderSide: BorderSide(color: c.outlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CMRadius.md),
        borderSide: BorderSide(color: c.outlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CMRadius.md),
        borderSide: BorderSide(color: c.signal, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.signal,
        foregroundColor: c.onSignal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CMRadius.md),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: CMSpacing.sp6,
          vertical: CMSpacing.sp3,
        ),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.outlineStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CMRadius.md),
        ),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.signal,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    extensions: [c],
  );
}