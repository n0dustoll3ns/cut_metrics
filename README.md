# cut_metrics — карта проекта

> Flutter-приложение для отслеживания метрик здоровья (вес, шаги, сон, активность).
> Данные берутся из Health Connect (Android) через пакет `health`.
> Последний code review + применение фиксов: 2026-06-29. Фаза 5 реализована: 2026-08-21.
> Фаза 6 «Стабилизация и полировка»: задание №1 (дизайн) выполнено 2026-09-02.
> **Задание №2 (реализация A–E) выполнено 2026-09-03** по `docs/phase6_implementation_task.md`:
> багфиксы из отчёта `docs/test_report_26-09-02.md` (ручной ввод побеждает — Tier 1 теперь по
> `sourceName`, т.к. `sourceId` на Android всегда пуст; `writeManualRecord` идемпотентен
> delete-then-write; снекбар ошибки записи), кеш подтверждений «Ок/Не ок» на пару
> (метрика+источник), «Не ок» = постоянный отказ источника; выбор источника на метрику
> («Авто»/приложение) со словарём имён; шаги — резолюция по сырым точкам «один источник
> на день» (aggregate-API удалены, техриски №2/№4 закрыты); ось дат на графиках
> (числа + «1 АВГ» на границе месяца, ≤8 меток, тултип «17 июл»); тёмная тема
> «приборная» через ThemeExtension (system/light/dark, дефолт system); DebugLog пишет
> «Ок»/«Не ок» и `sourceName`. Тесты: 148 зелёных, `flutter analyze` 4 info / 0 errors.

---

## Текущая структура (Фазы 1–6, актуальная)

```
lib/
  main.dart                        — 4 вкладки: Сегодня · Тренд · Саммари · Настройки
                                     + ThemeController (theme/darkTheme/themeMode)
  domain/
    data_source.dart               — DataSource { manual, external } (Tier 1/2)
    date_key.dart                  — DateKey + OnlyDate
    confirm_decision.dart          — ConfirmDecision { none, confirmed, refused } (Фаза 6 B)
    source_selection.dart          — SourceSelection { auto | app(package) } (Фаза 6 C)
    weight_day.dart, steps_day.dart— модели с source + sourcePackage + ==/hashCode
    health_data_processor.dart     — резолюция v2: sourcePackageOf (sourceName!),
                                     refused-фильтр, выбор источника, шаги «один
                                     источник на день» по сырым точкам, батч, computeEma
    sleep_analyzer.dart            — сон (перенос из old_proj + ASLEEP-приоритет, слои merge)
    sleep_day.dart                 — SleepDay (total = asleep | deep+light+rem)
    recommendation_engine.dart     — WeeklySummary/PaceStatus (чистый Dart)
    recommendation_config.dart     — ВСЕ константы Фазы 5 в одном месте
    activity_level.dart            — уровни 1–5 + калории (шаги×вес×0.0005 + добавка)
    metric_type.dart
  repo/
    health_repository.dart         — контракт (aggregate-методы удалены в Фазе 6)
    health_repository_impl.dart    — Health Connect через `health`; writeManualRecord
                                     идемпотентен (delete-then-write); наш пакет —
                                     по sourcePackageOf; логи с sourceName
    mock_health_repository.dart    — мок «как на Android» (sourceId='', пакет в
                                     sourceName) (+хелперы сна)
    health_permissions.dart        — permissions: kSleepTypes, kPermissionGroups
                                     (раздельные тихие проверки по каждому типу)
  services/
    settings_service.dart          — targetPace/activityLevel/lastSummaryShown +
                                     решения src_decision.<metric>.<package>,
                                     выбор src_selection.<metric>, theme_mode
    source_names.dart              — словарь package → имя (Google Fit и др.),
                                     fallback по последнему сегменту, обрезка беджа
    theme_controller.dart          — ThemeMode (system/light/dark) + персист
    debug_log.dart                 — in-memory журнал отладки (кольцевой буфер 1000, ChangeNotifier)
    app_settings_opener.dart       — MethodChannel → настройки приложения Android (кнопка разрешений)
  viewmodel/
    dashboard_view_model.dart      — кеши (вес/шаги/сон/EMA), сырые точки сессии,
                                     setRange, средние, computeWeeklySummary,
                                     confirm/refuse/reset + setSourceSelection
                                     (перерезолюция без похода в HC)
  ui/
    theme.dart                     — CMThemeColors (ThemeExtension, light/dark) +
                                     context.cmColors, cmTheme(Brightness)
    months.dart                    — kMonthsShort (даты интерфейса)
    source_badge.dart              — беджи «Из Google Fit»/«Ручной ввод» (имя источника)
    metric_card.dart, metric_card_state.dart — 7 состояний + бедж + меню «⋯»
    today_screen.dart              — сглаженный вес 60px + график 30д + карточки + баннер разрешений HC
    trend_screen.dart              — Неделя/Месяц/3 мес + среднесуточные (сон/шаги/ккал)
    summary_screen.dart            — саммари (статус, %/нед, ±кг, рекомендация)
    settings_screen.dart           — блок «Тема» + «Источники данных HC» + слайдер
                                     темпа + уровень активности + подпись версии
    source_settings_screen.dart    — подэкран «Источник: Вес/Шаги»: радио «Авто» +
                                     приложения со статусами Доверяем/Отклонён/Спрашивает
    debug_log_screen.dart          — журнал отладки: чипы-теги, «Только ошибки», «Копировать всё»
```

**Ключевая логика Фазы 5:**
- Саммари: пересчёт при каждом открытии за скользящие 7 дней; ≥3 взвешиваний в окне,
  иначе снекбар (гейт в `main.dart::_selectTab`); темп нормализуется к неделе
  (`Δ% × 7 / дни между крайними точками`); tolerance ±0.15 п.п.; дефолт темпа 0.8%.
- Активность = шаги×вес×0.0005 ккал + добавка уровня (ккал/кг/день: 0/1.5/3/4.5/6).
- Сон: правило «после 12:00 → следующий день»; ASLEEP приоритетнее стадий; merge по слоям.
- Данные грузятся за 90 дней (maxTrendDays) всегда — движок не зависит от сегмента Тренда.
- Тесты: 114 (все зелёные), `flutter analyze` — 4 info / 0 errors.

**Журнал отладки (2026-08-26, для проверки релиза на устройстве):**
- `DebugLog` (`lib/services/debug_log.dart`) — in-memory за сессию (не персистентно),
  кольцевой буфер 1000 записей, работает и в release. Теги: `app` (main), `vm` (ViewModel),
  `repo` (HealthRepositoryImpl), `perm` (permissions).
- Экран `lib/ui/debug_log_screen.dart`: новые записи сверху, чипы-фильтры по тегам +
  «Только ошибки», «Копировать всё» в буфер обмена (без новых зависимостей).
- Вход скрытый: 5 тапов по подписи версии внизу «Настроек» (пауза между тапами ≤ 3 с).
  Версия в подписи синхронизируется вручную с `pubspec.yaml`.
- Логи закрывают все 4 техриска Фаз 2/4: sourceId источников (№1), getTotalStepsInInterval (№2),
  delete() (№3), getHealthIntervalDataFromTypes по дням (№4) — в сообщениях тега `repo`.
- Тесты: `test/services/debug_log_test.dart` (10 шт.).

**Кнопка перехода в настройки разрешений (2026-08-26):**
- Если `load()` упёрся в отказ разрешений Health Connect — на «Сегодня» показывается
  `PermissionsBanner` (`lib/ui/today_screen.dart`, вместо `ErrorBox`) с кнопкой
  «Открыть настройки разрешений».
- Кнопка открывает страницу приложения в системных настройках Android
  (Настройки → Приложения → Cut Metrics → Разрешения) — решение пользователя от 2026-08-26.
- Реализация: `AppSettingsOpener` (`lib/services/app_settings_opener.dart`) → MethodChannel
  `cut_metrics/app_settings` → `MainActivity.kt` (`ACTION_APPLICATION_DETAILS_SETTINGS`,
  try/catch ActivityNotFoundException). Новых зависимостей нет.
- Возврат в приложение: `WidgetsBindingObserver` в `main.dart` (`didChangeAppLifecycleState`)
  → `DashboardViewModel.recheckPermissions()` — тихая проверка `Health.hasPermissions`
  (без системного диалога; с 2026-08-28 — раздельные вызовы по каждому типу, см. ниже); права выданы → `load()`, баннер исчезает; не выданы → баннер остаётся.
- ViewModel: флаг `permissionsDenied` + injectable `permissionCheck`/`permissionStatusCheck`
  (для тестов). Тесты: 4 новых в `test/viewmodel/dashboard_view_model_test.dart` (группа permissions).
- Проверено: `flutter test` — 104 зелёных; `flutter analyze` — 4 info / 0 errors;
  `flutter build apk --debug` — успешно (Kotlin-канал компилируется).
- ⚠️ Поведение кнопки и авто-исчезновение баннера после возврата — проверить на устройстве.

**Раздельная проверка разрешений по каждому типу (2026-08-28):**
- Тихая проверка `hasPermissions` идёт ОТДЕЛЬНЫМ вызовом на каждый тип (12 вызовов),
  сон разбит по стадиям — в журнале значение каждого пермишена отдельной строкой.
- `checkPermissionsPerType` (`lib/repo/health_permissions.dart`) пишет в DebugLog
  (тег `perm`): `Вес (WEIGHT, READ_WRITE) → true`, `Шаги (STEPS, READ_WRITE) → false`,
  `Сон (SLEEP_ASLEEP, READ) → true` … (9 стадий сна) … `Питание (NUTRITION, READ) → true`
  + строка «итог» со всеми значениями.
- ✅ `SLEEP_IN_BED` ИСКЛЮЧЁН из `kSleepTypes` (решение пользователя, 2026-08-28):
  это iOS-only тип (HealthKit «время в постели»); в пакете health 13.3.1/13.3.2
  его нет ни в `dataTypeKeysAndroid`, ни в нативном `mapToType` → `hasPermissions`
  для него ВСЕГДА false (при полностью выданных правах, подтверждено на устройстве),
  а пакетный `requestAuthorization` с ним в списке молча возвращает false БЕЗ
  системного диалога (баннер разрешений не исчезал). Данные сна не теряются:
  SleepAnalyzer читает ASLEEP + DEEP/LIGHT/REM из `SleepSessionRecord`.
  Регрессионный тест: каждый тип из `kPermissionGroups` обязан быть в
  `dataTypeKeysAndroid`.
- Группы `kPermissionGroups` (Вес/Шаги READ_WRITE, Сон 9×READ, Питание READ)
  ровно покрывают `kHealthDataTypes`/`kHealthDataAccess` (тест проверяет);
  итог — AND по всем (`allGranted`, null/false = не выдано).
- ✅ Фикс «поштучно все true, но load: permissions не выданы» (2026-08-28):
  нативный `requestAuthorization` пакета health 13.3.1/13.3.2 НЕ проверяет
  заранее выданные права — всегда запускает системную активити, и при уже
  выданных правах контракт HC возвращает ПУСТОЙ granted-set (только права,
  выданные в текущей сессии запроса), который плагин трактует как false
  (`HealthPlugin.kt`: `permissionGranted.isEmpty()` → `success(false)`) →
  вечный баннер при полностью выданных правах. Теперь
  `checkAndRequestPermissions` работает в 3 шага: (1) тихая проверка
  `checkPermissionsPerType` — всё выдано → `requestAuthorization` НЕ
  вызывается, в логе «все пермишены уже выданы — запрос не нужен»;
  (2) есть невыделенные → ОДИН пакетный `requestAuthorization` (один системный
  диалог — решение пользователя, UX онбординга не меняется); (3) возвращается
  итог тихой проверки ПОСЛЕ запроса (`allGranted`), а не сырой результат
  `requestAuthorization` — он ненадёжен (см. выше).
- `recheckPermissions` → `checkPermissionsPerType` + `allGranted`; сигнатуры
  injectable `permissionCheck`/`permissionStatusCheck` не менялись.
- Исключение одного типа не рушит остальные: error в логе, пункт `null`.
- Тесты: `test/repo/health_permissions_test.dart` (10 шт., injectable `probe`/`request`,
  включая регрессии про пустой granted-set и SLEEP_IN_BED). Всего 114 зелёных;
  `flutter analyze` — 4 info / 0 errors.

**Попутный фикс сборки (2026-08-26):** `ic_launcher_playstore_512.png` лежал в
`android/app/src/main/res/play_store/` — это ломало ЛЮБУЮ сборку
(`:app:package*Resources`: «The file name must end with .xml», файлы в `res/`
должны быть ресурсами). Каноническое место: `android/app/play_store/` (вне `res/`,
для стора). ⚠️ Дубль в `res/play_store/` вернулся повторно с коммитом «иконка
приложения» (b758452) и снова удалён — при добавлении иконок следить, чтобы в `res/`
не попадали не-XML файлы. Подробности и итоги полного починки сборки — секция
«Сборка APK» ниже.


Спеки Фаз 1–5 — в `docs/phase*.md`; изменения Фазы 5 по сбору требований —
`docs/phase5_ui_screens_and_activity_spec.md` + секция «Изменения» в конце
`docs/phase5_recommendation_and_indicator_spec.md`. Макеты экранов —
`docs/screen-*.html`.

---

## Архитектура СТАРОЙ версии (lib/old_proj, не компилируется с новым main)

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

- `_weightCache`, `_emaCache`, `_nutritionSessionsCache`, `_sleepCache`, `_stepsCache` — `Map<DateKey, T>`
  - `_nutritionSessionsCache` — хранит дедуплицированные кластеры (приёмы пищи) типа `List<MealSession>`, агрегация в `NutritionDay` происходит "на лету" в `_refreshChartData()`

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

- `filterByTopSource()` — фильтрация: оставляет только лучший источник за каждый день (индекс 0 = наивысший приоритет)
- `getSourcePriority()` — возвращает приоритет (0 = наивысший), неизвестные → низший
- `mergeWeightInto()` — `filterByTopSource` → last-wins по времени
- `computeEma(cache, period)` — EMA по всему кешу весов
- `mergeStepsInto()` — `filterByTopSource` → суммирование за день
- `mergeNutritionInto()` — `filterByTopSource` → кластеризация:
  1. `_convertToEntries()` — извлечение макросов и `sourceId`, фильтрация мусора (нули)
  2. `_clusterEntries()` — группировка точек в приёмы пищи (`_MealSession`): один источник + интервал ≤ 30 мин (`_mealGapMinutes`)
  3. `aggregateNutritionDay()` — суммирование кластеров в `NutritionDay`
- `mergeSleepInto()` — делегирует в `SleepAnalyzer` (с передачей `sourcePriorities`), `putIfAbsent` в кеш

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
| `shared_preferences` | Персистентное хранение приоритетов источников                                               |

---

## Сборка APK

`flutter build apk` → `build\app\outputs\flutter-apk\app-release.apk` (~55 МБ, 2026-08-26).

Подпись release — debug-ключом: `signingConfig = signingConfigs.getByName("debug")` в
`android/app/build.gradle.kts`. ⚠️ Без этой строки APK собирается, но НЕ подписывается —
на устройство не установится (проверка: `build-tools\<ver>\apksigner.bat verify --print-certs`,
jarsigner для этого бесполезен — видит только v1, а при minSdk 26 подпись v2).

⚠️ `build.gradle.kts` — Kotlin DSL: строки только в двойных кавычках, флаги —
`isMinifyEnabled = ...` / `isShrinkResources = ...` (Groovy-синтаксис вида
`minifyEnabled false` или одинарные кавычки ломают компиляцию скрипта —
«Unexpected tokens (use ';' to separate...)»). Починено 2026-08-26.

⚠️ Файлы для Play Store нельзя класть в `android/app/src/main/res/` — любой не-XML файл
там ломает ЛЮБУЮ сборку («The file name must end with .xml»). Каноническое место иконки
стора: `android/app/play_store/ic_launcher_playstore_512.png`. Дубль в `res/play_store/`
уже дважды возвращался с коммитами иконок (последний — b758452 «иконка приложения»,
удалён повторно 2026-08-26) — при добавлении иконок проверять, что в `res/` не попадают
не-XML файлы.

⚠️ Ограничение сборочной машины (общая RDP, ~24 ГБ RAM + pagefile 32 ГБ): в
`android/gradle.properties` намеренно занижены JVM-аппетиты Gradle
(`-Xmx3G`, `MaxMetaspaceSize=1G`, `workers.max=2`). Шаблонные значения (`-Xmx8G`,
metaspace 4G) исчерпывали commit-лимит памяти — сборка падала с
`System.OutOfMemoryException` в `flutter\bin\internal\update_engine_version.ps1`
("Unable to determine engine version") и ошибкой `:app:compileFlutterBuildRelease`
(починено 2026-08-18). Не возвращать большие значения без проверки свободной памяти
(`wmic OS get FreeVirtualMemory`).

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

## Приоритеты источников данных

Приложение позволяет настроить приоритеты источников для каждой метрики (вес, шаги, сон, питание). Это полезно, когда данные поступают из нескольких приложений/устройств.

### Как это работает

- Для каждого дня и каждой метрики выбирается **один источник** — самый приоритетный из тех, у которых есть данные за этот день
- Индекс 0 в списке = наивысший приоритет (верх списка)
- Настройки сохраняются между запусками (SharedPreferences)
- Кнопка настройки (иконка `tune`) находится в AppBar

### Логика по метрикам

| Метрика | Логика |
|---------|--------|
| Вес | Точка из лучшего источника, при нескольких за день — последняя по времени |
| Шаги | Сумма шагов только из лучшего источника за день |
| Сон | Интервалы только из лучшего источника за ночь |
| Питание | Кластеризация приёмов пищи только из лучшего источника за день |

### Архитектура

- `lib/domain/metric_type.dart` — enum `MetricType` (weight, steps, sleep, nutrition)
- `lib/services/source_priorities.dart` — `SourcePrioritiesService` (загрузка/сохранение в SharedPreferences)
- `lib/domain/processer.dart` — `filterByTopSource()` фильтрует точки перед агрегацией
- `lib/domain/sleep.dart` — `_filterByTopSource()` фильтрует по "дню сна"
- `lib/ui/source_priority_settings.dart` — диалог с `ReorderableListView`
- `lib/view_model.dart` — `setSourcePriorities()` пересчитывает все кеши из `_rawLog`

---

## Известные ограничения / TODO

- `WeightDay` не имеет `==`/`hashCode` — нет дедупликации при пересчёте EMA (производительность при больших данных)
- EMA пересчитывается целиком при каждом `setDate()` — потенциально тяжело при данных за год+
