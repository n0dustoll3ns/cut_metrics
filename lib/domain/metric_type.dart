/// Типы метрик, поддерживаемые приложением.
///
/// Фаза 7: добавлен `nutrition` — механика решений «Ок/Не ок» и выбора
/// источника Фазы 6 (B/C) переиспользуется автоматически (ключи
/// `src_decision.nutrition.<pkg>`, `src_selection.nutrition`).
enum MetricType {
  weight,
  steps,
  nutrition;
}
