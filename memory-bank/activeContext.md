# Active Context — Cut Metrics

> Обновляется по ходу работы (сообщением "update memory bank").

## Текущий фокус

Реализация фаз 1–5 по спекам в `docs/`, строго в этом порядке (см. `systemPatterns.md`,
"Порядок фаз реализации").

**Фаза 1 завершена** (2026-08-06): модель данных (`DataSource`, `WeightDay`, `StepsDay`),
резолюция источников (`HealthDataProcessor`), контракт репозитория, `MockHealthRepository`,
25 тестов — все зелёные, `flutter analyze` чист.

**Фаза 2 завершена** (2026-08-11): реализация `HealthRepositoryImpl` поверх пакета `health`,
`checkAndRequestPermissions`, обновлённые permissions в `AndroidManifest.xml`, `DateKey.startOfDay`/`endOfDay`,
дополненный `MockHealthRepository` с `recordingMethod`, 13 новых тестов (всего 38 — все зелёные).

**Фаза 3 завершена** (2026-08-11): UX-поток подтверждения значения. Создан первый UI-слой:
`DashboardViewModel` (ChangeNotifier, кеши, EMA, submit/cancel/getResolvedValue), графики
(`fl_chart` — LineChart веса+EMA, BarChart шагов), карточка метрики (5 состояний),
экраны Today/Dashboard. Дизайн-токены из дизайн-системы, `google_fonts` (Space Grotesk/Inter/Space Mono).
9 новых тестов (всего 47 — все зелёные), `flutter analyze` чист (2 info, 0 errors).

**Фаза 4 завершена** (2026-08-11): "Без локального кэша". Главное изменение — батчевая
агрегация шагов (`aggregateExternalStepsForRange`) вместо цикла из N вызовов по одному на
день. Подтверждено: нет записи данных на диск, кеши сессионные (документировано в коде),
резолюция батчевая (тесты проверяют: 1 вызов `aggregateExternalStepsForRange` + 2
`fetchRawData` при `load()`). 2 новых теста (всего 49 — все зелёные), `flutter analyze` чист (2 info, 0 errors).

**Фаза 5 завершена** (2026-08-21): `RecommendationEngine` + индикатор источника +
полная перестройка UI по макетам (4 вкладки). 41 новый тест (всего 90 — все зелёные),
`flutter analyze` 2 info / 0 errors. Ключевые решения зафиксированы в
`docs/phase5_ui_screens_and_activity_spec.md` + секция «Изменения» в
`docs/phase5_recommendation_and_indicator_spec.md` (слайдер вместо пресетов, дефолт 0.8%,
ежедневный пересчёт саммари вместо A.6, нормализация темпа к неделе, сон с ASLEEP-приоритетом
и послойным merge, активность = шаги×вес×0.0005 + уровни 1–5). Все константы Фазы 5 —
в `lib/domain/recommendation_config.dart` (требование пользователя: менять в одном месте).

**Сборка APK починена** (2026-08-18): `flutter build apk` падал с
`System.OutOfMemoryException` в `flutter\bin\internal\update_engine_version.ps1`
("Unable to determine engine version") — на общей RDP-машине исчерпывался commit-лимит,
Gradle был настроен на `-Xmx8G`/metaspace 4G. В `android/gradle.properties` занижены
JVM-аппетиты (`-Xmx3G`, metaspace 1G, `workers.max=2`). APK собирается:
`build\app\outputs\flutter-apk\app-release.apk` (~49 МБ). Подробности — `techContext.md`.

## ⚠️ Ожидает проверки на устройстве (Фаза 2+4, Definition of Done)

Четыре технических риска из `techContext.md`, которые нельзя проверить юнит-тестами:
1. **`sourceId`** — равен ли package name приложения (используется в `hasManualRecord`).
2. **`getTotalStepsInInterval`** — использует ли нативный `aggregate()` с приоритетом источников
   (используется в `aggregateExternalSteps`).
3. **`delete()`** — ограничен ли только записями своего приложения (используется в `deleteManualRecord`).
4. **`getHealthIntervalDataFromTypes`** (Фаза 4) — использует ли тот же нативный `aggregate()` с
   приоритетом источников, что и `getTotalStepsInInterval` (используется в `aggregateExternalStepsForRange`).

Код написан согласно спеке. Проверка выполняется пользователем на эмуляторе/устройстве
с Health Connect Toolbox. Компиляция и отсутствие ошибок = подтверждение.

## Следующий шаг

Фазы 1–5 реализованы. Дальше — проверка на устройстве (UI Фазы 5 + 4 технических риска
из `techContext.md` + баннер разрешений с кнопкой в настройки + сборка APK; для разбора
в release — журнал отладки, секция ниже), затем по отдельному запросу — Фаза 6
(AccessGate, не начинать без явного требования).

## Журнал отладки (2026-08-26)

Инструмент для проверки техрисков/UX на устройстве в **release**-сборке (там нет
`flutter logs`). Решения согласованы с пользователем: in-memory за сессию (без
персистентности), экспорт только «Копировать всё» через буфер, теги `app`/`vm`/`repo`/`perm`
(сон и движок рекомендаций НЕ инструментированы), фильтры: чипы по тегам + «Только ошибки».

- `lib/services/debug_log.dart` — `DebugLog` (синглтон, ChangeNotifier): уровни
  info/warn/error, кольцевой буфер 1000 записей (`ListQueue` из `dart:collection`),
  работает и в release (вызовы не обёрнуты в `kDebugMode`).
- `lib/ui/debug_log_screen.dart` — список живьём (новые сверху, Space Mono, error —
  Alert Rust, warn — Signal Cobalt), SelectionArea, «Копировать всё» / «Очистить».
- Вход скрытый: 5 тапов по подписи версии внизу «Настройки» (пауза между тапами ≤ 3 с,
  `_VersionLabel` в `settings_screen.dart`); версия в подписи синхронизируется
  вручную с `pubspec.yaml` — помнить при бампе версии.
- Инструментированы: `main.dart` (`app`), `DashboardViewModel.load/submit/cancel` (`vm`,
  Stopwatch-длительность load), `HealthRepositoryImpl` — все методы с sourceId и
  результатами (`repo`, закрывает техриски №1–№4 при проверке), `health_permissions` (`perm`).
  Бизнес-логика не менялась — только вызовы логирования + try/catch-rethrow для контекста
  исключений. Новых зависимостей нет.
- Тесты: `test/services/debug_log_test.dart` (10). Всего 100 зелёных,
  `flutter analyze` — 2 info / 0 errors (те же 2 базовых info, что и до изменений).

Созданные файлы: `lib/services/debug_log.dart`, `lib/ui/debug_log_screen.dart`,
`test/services/debug_log_test.dart`. Изменённые: `lib/main.dart`,
`lib/viewmodel/dashboard_view_model.dart`, `lib/repo/health_repository_impl.dart`,
`lib/repo/health_permissions.dart`, `lib/ui/settings_screen.dart`, `README.md`.

## Баннер разрешений + кнопка в системные настройки (2026-08-26)

Когда `load()` упирается в отказ разрешений Health Connect, экран «Сегодня» показывает
`PermissionsBanner` (вместо `ErrorBox`) с кнопкой «Открыть настройки разрешений».
Решение пользователя (2026-08-26): кнопка ведёт на страницу приложения в системных
настройках Android (`ACTION_APPLICATION_DETAILS_SETTINGS`), НЕ в настройки Health Connect.

- `lib/services/app_settings_opener.dart` — `AppSettingsOpener.openAppSettings()`:
  MethodChannel `cut_metrics/app_settings`, только Android, лог в DebugLog (тег `perm`).
- `android/app/src/main/kotlin/.../MainActivity.kt` — хендлер канала: `openAppDetails` →
  `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` (`ActivityNotFoundException` → false).
- `DashboardViewModel` — флаг `permissionsDenied` (сброс в начале `load()`),
  `recheckPermissions()`: тихая `Health.hasPermissions` (без системного диалога),
  права выданы → `load()`. Injectable `permissionCheck`/`permissionStatusCheck` —
  для юнит-тестов этой ветки.
- `main.dart` — `WidgetsBindingObserver` на `_AppShell`: `AppLifecycleState.resumed` →
  `recheckPermissions()` (пользователь вернулся из настроек — баннер исчезает и данные
  грузятся сами; прав нет — баннер остаётся, диалог НЕ всплывает принудительно).
- Новых зависимостей нет — в пакете `health` 13.3.1 нет API открытия настроек.
- Тесты: 4 новых в `test/viewmodel/dashboard_view_model_test.dart` (всего 104),
  `flutter analyze` — 4 info / 0 errors (2 базовых + 2 `prefer_initializing_formals`
  на новых injectable-параметрах, стиль конструктора сохранён).

Созданные файлы: `lib/services/app_settings_opener.dart`. Изменённые:
`MainActivity.kt`, `lib/viewmodel/dashboard_view_model.dart`, `lib/ui/today_screen.dart`,
`lib/main.dart`, `test/viewmodel/dashboard_view_model_test.dart`, `README.md`.
Верификация: `flutter test` 104 зелёных, `flutter analyze` 4 info / 0 errors,
`flutter build apk --debug` — успешно.

⚠️ Проверить на устройстве: открытие настроек по кнопке, авто-исчезновение баннера
после выдачи прав и возврата в приложение.

Попутный фикс: `ic_launcher_playstore_512.png` перемещён из
`android/app/src/main/res/play_store/` (ломал любую сборку — «The file name must end
with .xml» на `:app:packageDebugResources`, вернулось с коммитом «иконка приложения»)
в `android/app/play_store/` — вне `res/`, файл для стора, ресурсом быть не должен.

## Созданные файлы Фазы 5

- `docs/phase5_ui_screens_and_activity_spec.md` — ТЗ дополнений (экраны, активность, сон)
- `lib/domain/recommendation_config.dart` — ВСЕ константы Фазы 5 в одном месте
- `lib/domain/recommendation_engine.dart` — `PaceStatus`, `WeeklySummary`, `compute()`
- `lib/domain/activity_level.dart` — уровни 1–5, `stepsToKcal`, `dailyCaloriesBurned`
- `lib/domain/sleep_day.dart` — `SleepDay` (total = asleep | deep+light+rem)
- `lib/domain/sleep_analyzer.dart` — перенос из old_proj + ASLEEP-приоритет + слои merge
- `lib/services/settings_service.dart` — targetPace/activityLevel/lastSummaryShownDate
- `lib/ui/source_badge.dart` — беджи источника (B.2/B.3, без новых hex)
- `lib/ui/trend_screen.dart` — Неделя/Месяц/3 мес + среднесуточные
- `lib/ui/summary_screen.dart` — саммари по макету
- `lib/ui/settings_screen.dart` — слайдер темпа + уровень активности
- `test/domain/recommendation_engine_test.dart` — 11 тестов (статусы, границы, null)
- `test/domain/activity_level_test.dart` — 10 тестов
- `test/domain/sleep_analyzer_test.dart` — 9 тестов
- `test/services/settings_service_test.dart` — 6 тестов

## Изменённые файлы Фазы 5

- `lib/main.dart` — 4 вкладки, гейт «Саммари» (снекбар), SettingsService
- `lib/viewmodel/dashboard_view_model.dart` — кеш сна, `setRange`, средние,
  `computeWeeklySummary`, настройки, загрузка за 90 дней
- `lib/repo/mock_health_repository.dart` — `addSleepStage`/`addSleepAsleep`/`_makeIntervalPoint`
- `lib/ui/metric_card.dart` — интеграция `SourceBadge`, удалён старый бейдж «РУЧНОЙ ВВОД»
- `lib/ui/theme.dart` — `CMFonts.label` (Inter 600)
- `lib/ui/today_screen.dart` — перестроен по макету (сглаженный вес, график, кнопка саммари)
- `docs/phase5_recommendation_and_indicator_spec.md` — секция «Изменения по итогам сбора требований»
- `test/viewmodel/dashboard_view_model_test.dart` — fetchRawData 2→3, 8 новых тестов
- Удалены: `lib/ui/dashboard_view.dart`, `lib/ui/steps_chart.dart` (заменены Трендом)

## Явно вне скоупа прямо сейчас

- `lib/domain/data_source.dart` — enum `DataSource { manual, external }`
- `lib/domain/metric_type.dart` — enum `MetricType { weight, steps }`
- `lib/domain/date_key.dart` — `DateKey` (чистый Dart, без Flutter-зависимости)
- `lib/domain/weight_day.dart` — `WeightDay` с `source` + `==`/`hashCode`
- `lib/domain/steps_day.dart` — `StepsDay` с `source` + `==`/`hashCode`
- `lib/domain/health_data_processor.dart` — `resolveWeightForDate`/`resolveStepsForDate` + батчевые варианты
- `lib/repo/health_repository.dart` — абстрактный контракт
- `lib/repo/mock_health_repository.dart` — мок для тестов
- `test/domain/health_data_processor_test.dart` — 25 тестов

## Созданные файлы Фазы 2

- `lib/repo/health_repository_impl.dart` — `HealthRepositoryImpl` (чтение/запись в Health Connect)
- `lib/repo/health_permissions.dart` — `checkAndRequestPermissions`, `kHealthDataTypes`, `kHealthDataAccess`
- `test/domain/phase2_repository_test.dart` — 13 тестов (recordingMethod, write/delete для шагов, DateKey)

## Изменённые файлы Фазы 2

- `lib/domain/date_key.dart` — добавлены `startOfDay` / `endOfDay`
- `lib/repo/mock_health_repository.dart` — `recordingMethod` в mock-точках, геттер `points`
- `android/app/src/main/AndroidManifest.xml` — `WRITE_WEIGHT`, `WRITE_STEPS` permissions

## Созданные файлы Фазы 3

- `lib/viewmodel/dashboard_view_model.dart` — `DashboardViewModel` + `ResolvedValue`
- `lib/ui/theme.dart` — дизайн-токены (CMColors, CMRadius, CMSpacing, CMFonts), `cmTheme()`
- `lib/ui/metric_card_state.dart` — enum `MetricCardState`, `baseStateFromValue`
- `lib/ui/metric_card.dart` — `MetricCard` (5 состояний, StatefulWidget)
- `lib/ui/weight_chart.dart` — `WeightChart` (LineChart веса+EMA), `ChartCard`
- `lib/ui/steps_chart.dart` — `StepsChart` (BarChart шагов)
- `lib/ui/dashboard_view.dart` — `DashboardView` (графики + карточка по тапу)
- `lib/ui/today_screen.dart` — `TodayScreen` (инлайн карточки веса и шагов)
- `test/viewmodel/dashboard_view_model_test.dart` — 9 тестов

## Изменённые файлы Фазы 3

- `lib/domain/health_data_processor.dart` — добавлен `computeEma` (перенос из старого кода)
- `lib/main.dart` — Provider-инжекция, тема, нижняя навигация (Today/Dashboard)
- `pubspec.yaml` — добавлен `google_fonts`

## Изменённые файлы Фазы 4

- `lib/repo/health_repository.dart` — добавлен `aggregateExternalStepsForRange` в контракт
- `lib/repo/health_repository_impl.dart` — реализация через `getHealthIntervalDataFromTypes(interval: 1440)`
- `lib/repo/mock_health_repository.dart` — `aggregateExternalStepsForRange`, счётчики вызовов, `_resolveAggregatedSteps`
- `lib/viewmodel/dashboard_view_model.dart` — цикл N вызовов заменён на один батчевый, документация кешей
- `test/viewmodel/dashboard_view_model_test.dart` — 2 новых теста (батчевый вызов, количество fetchRawData)

## Явно вне скоупа прямо сейчас

- AccessGate / монетизация / paywall — сознательно отложено, отдельная будущая фаза.
- Nutrition / КБЖУ — не трогать ни в одной из фаз 1–5.
- Sleep / `SleepAnalyzer` — не трогать, ручной ввод сна не планируется.
- Оптимизация пересчёта EMA — известный TODO, принимается как есть, не решается сейчас.
- Логика рефидов (см. `productContext.md`) — открытый вопрос продукта, не задача разработки.

## Как действовать при неоднозначности

Если что-то в спеке фазы неочевидно или спека противоречит увиденному в коде — задать вопрос,
а не выбирать самостоятельно и молчать об этом. Это установленный для этого проекта способ
работы (см. `.clinerules`).