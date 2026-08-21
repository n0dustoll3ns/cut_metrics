import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:flutter/material.dart';

/// Бедж источника данных (Фаза 5, часть B — B.1–B.3).
///
/// По таблице B.6:
/// - `autoUnconfirmed` → [DataSource.external] → «Из Health Connect»:
///   фон `surface2`, рамка `outline`, текст `inkMuted`, точка `noise`.
/// - `manualConfirmed` → [DataSource.manual] → «Ручной ввод»:
///   фон `signalTint`, рамка `outline`, текст `ink`, точка `signal`.
///
/// Форма — pill (`.badge` дизайн-системы, border-radius 999px → [StadiumBorder]),
/// точка-индикатор 8px + текст — бледная подложка, НЕ сплошная заливка
/// (принцип AA-контраста из дизайн-системы). Все цвета — существующие токены
/// `theme.dart`, новых hex нет (DoD B.7 п.2).
class SourceBadge extends StatelessWidget {
  final DataSource source;

  const SourceBadge({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final isManual = source == DataSource.manual;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CMSpacing.sp2 + CMSpacing.sp1,
        vertical: CMSpacing.sp1 + 2,
      ),
      decoration: ShapeDecoration(
        color: isManual ? CMColors.signalTint : CMColors.surface2,
        shape: StadiumBorder(
          side: BorderSide(color: isManual ? CMColors.outline : CMColors.outline),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isManual ? CMColors.signal : CMColors.noise,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: CMSpacing.sp2),
          Text(
            isManual ? 'Ручной ввод' : 'Из Health Connect',
            style: CMFonts.label(
              size: 11,
              color: isManual ? CMColors.ink : CMColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
