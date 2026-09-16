/// «8620» → «8 620» — разделитель разрядов (как в макетах Фазы 5–7).
String formatThousands(num value) => value.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ' ',
    );

/// Форматирует ккал со знаком: «−530» / «+120» / «0» (для баланса).
String formatSignedKcal(num value) {
  final v = value.round();
  if (v == 0) return '0';
  return v < 0 ? '−${formatThousands(v.abs())}' : '+${formatThousands(v)}';
}
