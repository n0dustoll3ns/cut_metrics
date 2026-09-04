import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/services/source_names.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:flutter/material.dart';

/// Бедж источника данных (Фаза 5, часть B — B.1–B.3; Фаза 6, C.3 — имя приложения).
///
/// По таблице B.6 + Фаза 6:
/// - `autoUnconfirmed`/`autoConfirmed` → [DataSource.external] →
///   «Из Google Fit» и т.п. ([sourceBadgeLabel] по `sourcePackage`):
///   фон `surface2`, рамка `outline`, текст `inkMuted`, точка `noise`.
/// - `manualConfirmed` → [DataSource.manual] → «Ручной ввод»:
///   фон `signalTint`, рамка `outline`, текст `ink`, точка `signal`.
///
/// Форма — pill (`.badge` дизайн-системы, border-radius 999px → [StadiumBorder]),
/// точка-индикатор 8px + текст — бледная подложка, НЕ сплошная заливка
/// (принцип AA-контраста из дизайн-системы). Имя источника — по словарю
/// `source_names.dart` с fallback и обрезкой ~16 символов. Цвета — роли
/// текущей темы (`context.cmColors`), новых hex нет.
class SourceBadge extends StatelessWidget {
  final DataSource source;

  /// Пакет приложения-источника для внешних данных (Фаза 6, C.3).
  /// `null` → fallback «Из Health Connect».
  final String? sourcePackage;

  const SourceBadge({super.key, required this.source, this.sourcePackage});

  @override
  Widget build(BuildContext context) {
    final isManual = source == DataSource.manual;
    final colors = context.cmColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CMSpacing.sp2 + CMSpacing.sp1,
        vertical: CMSpacing.sp1 + 2,
      ),
      decoration: ShapeDecoration(
        color: isManual ? colors.signalTint : colors.surface2,
        shape: StadiumBorder(
          side: BorderSide(color: colors.outline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isManual ? colors.signal : colors.noise,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: CMSpacing.sp2),
          Text(
            isManual ? 'Ручной ввод' : sourceBadgeLabel(sourcePackage),
            style: CMFonts.label(
              size: 11,
              color: isManual ? colors.ink : colors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
