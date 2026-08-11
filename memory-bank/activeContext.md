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

Фаза 5 (`docs/phase5_recommendation_and_indicator_spec.md`) — RecommendationEngine и индикатор
источника. Чистый Dart-класс: темп изменения веса (%/нед), статус (в темпе / медленно / быстро),
рекомендация по калориям. UI-индикатор источника (manual/external) на карточках.

## Созданные файлы Фазы 1

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