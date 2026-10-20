/// Модели трассы расчёта «Как рассчитано» (CalcDetail).
///
/// Трасса объясняет, как получено любое вычисленное число на экранах:
/// исходные данные с источниками → шаги → итог, равный числу на экране.
/// Главное ограничение (`docs/calc_detail_implementation_task.md`): формулы
/// и правила расчётов НЕ меняются — билдеры трасс (`calc_trace_builders.dart`)
/// только читают результаты существующих функций домена.
///
/// Чистый Dart — без импортов Flutter/Health (паттерн остальных доменных
/// моделей). Все строки текста (значения, подписи, формулы) билдеры готовят
/// заранее, в формате соответствующего экрана — UI только отображает.
library;

/// Откуда взято исходное число (бейдж в UI: HEALTH CONNECT / РУЧНОЙ ВВОД /
/// НАСТРОЙКИ / ФОРМУЛА / РАСЧЁТ).
enum TraceSourceKind { healthConnect, manual, settings, formula, computed }

/// Одна строка секции «Исходные данные».
class TraceInput {
  /// Подпись: «Шаги за 22 сентября».
  final String label;

  /// Значение в формате экрана: «12 400».
  final String valueText;

  /// Источник числа (бейдж).
  final TraceSourceKind kind;

  /// Пакет приложения-источника: «Samsung Health» (для
  /// [TraceSourceKind.healthConnect]/[TraceSourceKind.manual]); отображаемое
  /// имя резолвит UI через словарь `source_names.dart`.
  final String? sourceName;

  /// Записи источника: «2 000 + 4 500 + 1 500».
  final String? recordsText;

  /// Примечание к входу: «день не завершён», «см. трассу калорий».
  final String? note;

  /// `true` → конкурент: источник с данными за день, НЕ попавший в расчёт.
  /// Скрыт до чекбокса «Показать данные, не попавшие в расчёт».
  final bool notUsed;

  /// Почему конкурент не учтён: «сумма меньше» / «меньше покрытие дней» /
  /// «источник отклонён» / «проиграл авто-правилу».
  final String? notUsedReason;

  const TraceInput({
    required this.label,
    required this.valueText,
    required this.kind,
    this.sourceName,
    this.recordsText,
    this.note,
    this.notUsed = false,
    this.notUsedReason,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceInput &&
          label == other.label &&
          valueText == other.valueText &&
          kind == other.kind &&
          sourceName == other.sourceName &&
          recordsText == other.recordsText &&
          note == other.note &&
          notUsed == other.notUsed &&
          notUsedReason == other.notUsedReason;

  @override
  int get hashCode => Object.hash(
        label,
        valueText,
        kind,
        sourceName,
        recordsText,
        note,
        notUsed,
        notUsedReason,
      );

  @override
  String toString() =>
      'TraceInput($label: $valueText, $kind${notUsed ? ', не учтено: $notUsedReason' : ''})';
}

/// Один шаг секции «Расчёт».
class TraceStep {
  /// Что делаем: «Суммируем записи победившего источника».
  final String title;

  /// Подстановка: «2 000 + 4 500 + 1 500».
  final String? formulaText;

  /// Результат шага: «= 8 000».
  final String? resultText;

  /// Примечание: «агрегат HC не используется — резолюция по сырым точкам».
  final String? note;

  const TraceStep({required this.title, this.formulaText, this.resultText, this.note});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceStep &&
          title == other.title &&
          formulaText == other.formulaText &&
          resultText == other.resultText &&
          note == other.note;

  @override
  int get hashCode => Object.hash(title, formulaText, resultText, note);

  @override
  String toString() => 'TraceStep($title${formulaText != null ? ' · $formulaText' : ''}'
      '${resultText != null ? ' · $resultText' : ''})';
}
/// Строка таблицы «дата · значение · источник» (среднесуточные, §3.5).
///
/// Для многозначных таблиц (энергобаланс недели: приход · расход · баланс,
/// §3.7) используются [value2Text]/[value3Text], UI рисует дополнительные
/// колонки только при их наличии.
class TraceDayRow {
  final String dateText;
  final String valueText;
  final String? value2Text;
  final String? value3Text;
  final String? sourceName;

  const TraceDayRow({
    required this.dateText,
    required this.valueText,
    this.value2Text,
    this.value3Text,
    this.sourceName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceDayRow &&
          dateText == other.dateText &&
          valueText == other.valueText &&
          value2Text == other.value2Text &&
          value3Text == other.value3Text &&
          sourceName == other.sourceName;

  @override
  int get hashCode => Object.hash(dateText, valueText, value2Text, value3Text, sourceName);

  @override
  String toString() =>
      'TraceDayRow($dateText: $valueText${sourceName != null ? ' · $sourceName' : ''})';
}

/// Строка цепочки EMA «дата · сырой вес · EMA» (+ флаг рестарта серии).
///
/// [seriesRestart] — `true` для первой точки после разрыва 5+ пустых дней:
/// серия обрывается, скользящее стартует заново с веса этой точки.
class TraceEmaRow {
  final String dateText;
  final double rawWeight;
  final double ema;
  final bool seriesRestart;

  const TraceEmaRow({
    required this.dateText,
    required this.rawWeight,
    required this.ema,
    this.seriesRestart = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceEmaRow &&
          dateText == other.dateText &&
          rawWeight == other.rawWeight &&
          ema == other.ema &&
          seriesRestart == other.seriesRestart;

  @override
  int get hashCode => Object.hash(dateText, rawWeight, ema, seriesRestart);

  @override
  String toString() =>
      'TraceEmaRow($dateText: raw $rawWeight → ema $ema${seriesRestart ? ' (рестарт)' : ''})';
}

/// Готовая трасса для нижнего листа «Как рассчитано».
class CalcTrace {
  /// Заголовок: «Шаги».
  final String title;

  /// Подзаголовок: «22 сентября» / «среднесуточные · окно 30 дней».
  final String? subtitle;

  /// Секция «Исходные данные» (входы + конкуренты за чекбоксом).
  final List<TraceInput> inputs;

  /// Секция «Расчёт».
  final List<TraceStep> steps;

  /// Итог — СТРОГО в формате экрана: «8 000».
  final String resultText;

  /// Единица итога: «шагов».
  final String? resultUnit;

  /// Доп-итоги: «−0.7 кг за неделю», покрытие «по 41 дн.».
  final String? resultNote;

  /// Таблица дней среднесуточных/энергобаланса (если есть).
  final List<TraceDayRow>? dayRows;

  /// `true` при диапазоне 90 дней — таблица свёрнута до кнопки
  /// «Показать все дни (N)» (решение пользователя 2026-09-23, п. 5).
  final bool dayRowsCollapsedByDefault;

  /// Цепочка EMA «дата · сырой вес · EMA» (темп, сглаженный вес) — скрыта до
  /// кнопки «Показать все шаги EMA».
  final List<TraceEmaRow>? emaRows;

  const CalcTrace({
    required this.title,
    this.subtitle,
    required this.inputs,
    required this.steps,
    required this.resultText,
    this.resultUnit,
    this.resultNote,
    this.dayRows,
    this.dayRowsCollapsedByDefault = false,
    this.emaRows,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalcTrace &&
          title == other.title &&
          subtitle == other.subtitle &&
          _listEq(inputs, other.inputs) &&
          _listEq(steps, other.steps) &&
          resultText == other.resultText &&
          resultUnit == other.resultUnit &&
          resultNote == other.resultNote &&
          _listEq(dayRows, other.dayRows) &&
          dayRowsCollapsedByDefault == other.dayRowsCollapsedByDefault &&
          _listEq(emaRows, other.emaRows);

  /// Поэлементное сравнение списков (`List.==` в Dart — identity).
  static bool _listEq<T>(List<T>? a, List<T>? b) {
    if (a == null || b == null) return identical(a, b);
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        title,
        subtitle,
        Object.hashAll(inputs),
        Object.hashAll(steps),
        resultText,
        resultUnit,
        resultNote,
        dayRows == null ? null : Object.hashAll(dayRows!),
        dayRowsCollapsedByDefault,
        emaRows == null ? null : Object.hashAll(emaRows!),
      );

  @override
  String toString() => 'CalcTrace($title${subtitle != null ? ' · $subtitle' : ''} → $resultText)';
}

