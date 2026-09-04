import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';

/// Состояния карточки метрики на дату (Фаза 3, секция 3; Фаза 6, B.4 — новые).
///
/// Семь состояний для пары (дата, тип метрики):
///
/// | Состояние           | Условие входа                                    |
/// |---------------------|--------------------------------------------------|
/// | `loading`           | Идёт резолюция (изначально/перезагрузка)         |
/// | `missing`           | Резолюция вернула `null`, источников с данными нет|
/// | `autoUnconfirmed`   | `source == external`, решение «спрашивать»        |
/// | `autoConfirmed`     | решение «доверяем» ИЛИ источник выбран явно       |
/// | `sourceRefused`     | все источники с данными за дату «отклонены»       |
/// | `manualEntryActive` | Нажали «Не ок» ИЛИ были в `missing`               |
/// | `manualConfirmed`   | `source == manual`                                |
///
/// `manualEntryActive` — чисто UI-состояние (локальный флаг виджета),
/// не выводится из данных. Остальные состояния выводятся из [ResolvedValue].
enum MetricCardState {
  loading,
  missing,
  autoUnconfirmed,
  autoConfirmed,
  sourceRefused,
  manualEntryActive,
  manualConfirmed,
}

/// Утилита для вывода базового состояния карточки из [ResolvedValue].
///
/// `manualEntryActive` не выводится здесь — это локальный флаг виджета.
/// Этот метод определяет «базовое» состояние из данных:
/// - `null` + есть отклонённые источники с данными → `sourceRefused`;
/// - `null` без данных → `missing`;
/// - `manual` → `manualConfirmed`;
/// - `external` → `autoUnconfirmed` (тише ли карточка — решает вызывающий
///   код через `DashboardViewModel.isSourceTrusted`, см. `MetricCard`).
MetricCardState baseStateFromValue(
  ResolvedValue<num>? value, {
  bool sourceRefused = false,
}) {
  if (value == null) {
    return sourceRefused ? MetricCardState.sourceRefused : MetricCardState.missing;
  }
  return value.source == DataSource.manual
      ? MetricCardState.manualConfirmed
      : MetricCardState.autoUnconfirmed;
}