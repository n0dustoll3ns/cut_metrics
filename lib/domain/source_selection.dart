/// Выбранный источник данных для метрики — Фаза 6, часть C.
///
/// Один источник на метрику (вес/шаги), без сортировки списка. Дефолт —
/// [SourceSelection.auto]: вся логика Фаз 1–5 (вес — last-wins, шаги —
/// «один источник на день»). Выбор конкретного приложения сужает резолюцию
/// до его точек и означает доверие: карточка не спрашивает «Ок / Не ок».
///
/// Хранится в `SettingsService` (`src_selection.<metric>`).
class SourceSelection {
  /// Пакет выбранного приложения; `null` — режим «Авто».
  final String? package;

  const SourceSelection.auto() : package = null;

  const SourceSelection.app(this.package);

  bool get isAuto => package == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceSelection && package == other.package;

  @override
  int get hashCode => package.hashCode;

  @override
  String toString() =>
      isAuto ? 'SourceSelection.auto' : 'SourceSelection.app($package)';
}
