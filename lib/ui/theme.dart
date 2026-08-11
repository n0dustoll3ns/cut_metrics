import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Дизайн-токены Cut Metrics — перенос значений из `docs/design-system.html`.
///
/// 6 брендовых цветов + производные нейтральные. Не изобретать новые hex —
/// всё нужное для текущих фаз уже есть в дизайн-системе (см. techContext.md).
class CMColors {
  CMColors._();

  // ─── Core palette ───────────────────────────────────────────────────────────
  static const bg = Color(0xFFF3F5F6); // Instrument Grey — фон/канва
  static const ink = Color(0xFF14171A); // Deep Ink — основной текст
  static const noise = Color(0xFF9CA3AF); // Noise Grey — сырые точки, второстепенное
  static const signal = Color(0xFF2A5DB0); // Signal Cobalt — тренд, CTA
  static const steady = Color(0xFF1F9D6C); // Steady Green — статус "в темпе"
  static const alert = Color(0xFFB23A2E); // Alert Rust — отклонение

  // ─── Derived neutrals (surface layer) ───────────────────────────────────────
  static const surface0 = Color(0xFFFFFFFF); // карточки
  static const surface1 = bg; // = Instrument Grey
  static const surface2 = Color(0xFFE7EAEC); // ховеры, заполненные области
  static const outline = Color(0xFFD7DBDE);
  static const outlineStrong = Color(0xFFC2C7CC);
  static const inkMuted = Color(0xFF4B5259);

  // ─── Derived signal tones ───────────────────────────────────────────────────
  static const signalHover = Color(0xFF234C8D);
  static const signalPress = Color(0xFF1D3F73);
  static const signalTint = Color(0xFFE7EEF8);

  // ─── Status tint backgrounds (для badge-ей) ─────────────────────────────────
  static const steadyTint = Color(0xFFE4F5EE);
  static const steadyBorder = Color(0xFFBEE3D2);
  static const alertTint = Color(0xFFFBEAE8);
  static const alertBorder = Color(0xFFEFC5BF);

  // ─── Alpha variants ─────────────────────────────────────────────────────────
  static const noiseLight = Color(0x559CA3AF); // точки на графике (полупрозрачные)
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
class CMFonts {
  CMFonts._();

  /// Числа: Space Grotesk, табличные цифры.
  static TextStyle metric({
    double size = 26,
    FontWeight weight = FontWeight.w500,
    Color color = CMColors.ink,
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
    Color color = CMColors.ink,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Body: Inter 400.
  static TextStyle body({
    double size = 16,
    Color color = CMColors.ink,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.5,
      );

  /// Caption/моно: Space Mono uppercase — даты, единицы, подписи.
  static TextStyle caption({
    double size = 12,
    Color color = CMColors.noise,
  }) =>
      GoogleFonts.spaceMono(
        fontSize: size,
        color: color,
        letterSpacing: 0.05,
      );
}

/// Тема приложения — Material 3, настроенная на токены дизайн-системы.
ThemeData cmTheme() {
  final base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: CMColors.bg,
    colorScheme: ColorScheme.light(
      primary: CMColors.signal,
      onPrimary: Colors.white,
      secondary: CMColors.signal,
      surface: CMColors.surface0,
      onSurface: CMColors.ink,
      error: CMColors.alert,
      outline: CMColors.outline,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    cardTheme: CardThemeData(
      color: CMColors.surface0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CMRadius.lg),
        side: const BorderSide(color: CMColors.outline),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CMColors.surface0,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: CMSpacing.sp4,
        vertical: CMSpacing.sp3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CMRadius.md),
        borderSide: const BorderSide(color: CMColors.outlineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CMRadius.md),
        borderSide: const BorderSide(color: CMColors.outlineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CMRadius.md),
        borderSide: const BorderSide(color: CMColors.signal, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: CMColors.signal,
        foregroundColor: Colors.white,
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
        foregroundColor: CMColors.ink,
        side: const BorderSide(color: CMColors.outlineStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CMRadius.md),
        ),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CMColors.signal,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
  );
}