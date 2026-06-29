# cut_metrics — карта проекта

> Flutter-приложение для отслеживания метрик здоровья (вес, шаги, сон, питание).
> Данные берутся из Health Connect (Android) через пакет `health`.
> Последний code review + применение фиксов: 2026-06-29.

---

## Архитектура

```
main.dart
  └── AppView (MultiProvider)
        ├── ViewModel (ChangeNotifier)          ← view_model.dart
        └── Scaffold
              ├── AppBar: TimeNav               ← ui/time_nav.dart
              └── Body: DashboardView           ← dashboard_view.dart
                    ├── StepsChart              ← ui/steps_chart.dart
                    ├── NutritionChart          ← ui/nutrition_chart.dart
                    ├── _ChartCard(Weight+EMA)
                    └── _ChartCard(Sleep)
```

**Слои:**

- `repo/` — доступ к Health Connect API
- `domain/` — бизнес-логика, модели данных
- `view_model.dart` — оркестрация, кеширование, состояние UI
- `ui/` + `dashboard_view.dart` — виджеты

---

## Файлы и их роли

### `lib/main.dart`

- Точка входа. `_useMock = kDebugMode` — переключение на MockRepository в debug.
- `AppView` создаёт `ViewModel` через `MultiProvider`.

### `lib/view_model.dart` — `ViewModel extends ChangeNotifier`

**Публичное состояние:** `start`, `end`, `isLoading`, `error`, `weightData`, `emaData`, `nutritionData`, `sleepData`, `stepsData`

**Кеши** (всё загруженное, не только текущий диапазон):

- `_weightCache`, `_emaCache`, `_nutritionCache`, `_sleepCache`, `_stepsCache` — `Map<DateKey, T>`

**Ключевая логика:**

- `_loadedRange` — загруженный диапазон, не перезапрашивается
- `_unloadedRange` → `getUncoveredRange()` — вычисляет что догрузить
- `_load()` — параллельный `Future.wait` для weight/steps/sleep/nutrition
- `_loadGeneration` (int) — защита от race condition при быстрой смене дат
- `_emaPeriod` — 3/5/10 дней в зависимости от длины диапазона
- `setDate({start, end})` — публичный API смены диапазона

### `lib/domain.dart`

Модели: `SleepDay`, `StepsDay`, вспомогательная `getMonthTitle(int)`.

### `lib/domain/weight.dart` — `WeightDay`

`{ DateKey date, double weight }`

### `lib/domain/nutrition.dart` — `NutritionDay`

`{ DateKey date, double calories, protein, fat, carbs }` + `get totalGrams`

### `lib/domain/sleep.dart` — `SleepAnalyzer`

Пайплайн: фильтрация → сортировка → `_mergeIntervals` (overwrite logic) → `_aggregateByDay`.

**Правило дня сна:** если интервал начался после 12:00 → относится к следующему дню.

`_SleepInterval` — иммутабельный (все поля `final`), мутация через `withEnd(DateTime)`.

`_trackedTypes` = `{SLEEP_DEEP, SLEEP_LIGHT, SLEEP_REM}` — вместо switch.

### `lib/domain/processer.dart` — `HealthDataProcessor`

- `mergeWeightInto()` — last-wins: сортировка по времени, перезапись при дублях за день
- `computeEma(cache, period)` — EMA по всему кешу весов
- `mergeStepsInto()` — суммирование за день
- `mergeNutritionInto()` — первое вхождение за день (skip duplicates)
- `mergeSleepInto()` — делегирует в `SleepAnalyzer`, `putIfAbsent` в кеш

### `lib/domain/date_extension.dart`

- `OnlyDate` extension: `onlyDate`, `isInsideInterval(start, end)` — **включает границы** (`!isBefore && !isAfter`)
- `DateKey extends ValueKey<DateTime>` — нормализован до дня, используется как ключ Map
- `Coverage` extension на `DateTimeRange`:
  - `isFullyCoveredBy(other)`
  - `getUncoveredRange(other)` → `null` если покрыт, `DateTimeRange` иначе
- `DateListExtension`: `earliestDate`, `latestDate`

### `lib/repo/health.dart` — `HealthRepository`

- `_configFuture` — мемоизированный Future, защита от двойного `configure()`
- `ensureConfigured()` → `_configFuture ??= _doConfigured()`
- `checkAndRequestPermissions(types)` — проверяет SDK status, hasPermissions, запрашивает
- `fetchRawData({types, startDate, endDate})`

### `lib/repo/health_mock.dart` — `MockHealthRepository`

Генерирует детерминированные тестовые данные. Sleep: `dateFrom=23:30`, `dateTo=+1день 02:00/07:00`.

### `lib/dashboard_view.dart`

- `DashboardView` — `SingleChildScrollView` с 4 графиками
- `_ChartCard` — общий виджет для графиков weight и sleep: isLoading/isEmpty/legend/child
- `LegendItem` — цветная точка + подпись
- Графики: `LineChart` (вес+EMA), `BarChart` (стековый сон)

### `lib/ui/nutrition_chart.dart` — `NutritionChart`

Стековый `BarChart` макронутриентов (белки / жиры / углеводы). Ось Y в граммах. Легенда встроенная (`_LegendDot`).

### `lib/ui/steps_chart.dart` — `StepsChart`

`BarChart`. Целевая линия `targetSteps = 12000` (deepOrange). Ось Y в тысячах (K).

### `lib/ui/time_nav.dart` — `TimeNav implements PreferredSizeWidget`

Два `DatePicker`. End-пикер: `firstDate: start` (нельзя выбрать конец раньше начала).

---

## Зависимости (пакеты)

| Пакет        | Для чего                                                                                                   |
| ------------ | ---------------------------------------------------------------------------------------------------------- |
| `health`     | Health Connect API, типы `HealthDataType`, `HealthDataPoint`, `NumericHealthValue`, `NutritionHealthValue` |
| `provider`   | `ChangeNotifierProvider`, `context.select`, `context.read`                                                 |
| `fl_chart`   | `LineChart`, `BarChart`                                                                                    |
| `collection` | `.sorted()` на списках                                                                                     |
| `intl`       | `DateFormat.yMd()`                                                                                         |

---

## Типы данных Health Connect

```dart
_sleepTypes    = [SLEEP_DEEP, SLEEP_LIGHT, SLEEP_REM]
_weightTypes   = [WEIGHT]
_nutritionTypes = [NUTRITION]
_stepsTypes    = [STEPS]
_allTypes      = все вышеперечисленные (для запроса разрешений)
```

---

## Известные ограничения / TODO

- `WeightDay` не имеет `==`/`hashCode` — нет дедупликации при пересчёте EMA (производительность при больших данных)
- EMA пересчитывается целиком при каждом `setDate()` — потенциально тяжело при данных за год+
