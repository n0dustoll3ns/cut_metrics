import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';

/// Состояния карточки метрики на дату (Фаза 3, секция 3).
///
/// Пять состояний для пары (дата, тип метрики):
///
/// | Состояние          | Условие входа                          |
/// |--------------------|----------------------------------------|
/// | `loading`          | Идёт резолюция (изначально/перезагрузка)|
/// | `missing`          | Резолюция вернула `null`               |
/// | `autoUnconfirmed`  | `source == external`                   |
/// | `manualEntryActive`| Нажали "не ок" ИЛИ были в `missing`    |
/// | `manualConfirmed`  | `source == manual`                     |
///
/// `manualEntryActive` — чисто UI-состояние (локальный флаг виджета),
/// не выводится из данных. Остальные состояния выводятся из [ResolvedValue].
enum MetricCardState { loading, missing, autoUnconfirmed, manualEntryActive, manualConfirmed }

/// Утилита для вывода состояния карточки из [ResolvedValue].
///
/// `manualEntryActive` не выводится здесь — это локальный флаг виджета.
/// Этот метод определяет "базовое" состояние из данных.
MetricCardState baseStateFromValue(ResolvedValue<num>? value) {
  if (value == null) return MetricCardState.missing;
  return value.source == DataSource.manual
      ? MetricCardState.manualConfirmed
      : MetricCardState.autoUnconfirmed;
}