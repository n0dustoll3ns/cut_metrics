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

## ⚠️ Ожидает проверки на устройстве (Фаза 2, Definition of Done)

Три технических риска из `techContext.md`, которые нельзя проверить юнит-тестами:
1. **`sourceId`** — равен ли package name приложения (используется в `hasManualRecord`).
2. **`getTotalStepsInInterval`** — использует ли нативный `aggregate()` с приоритетом источников
   (используется в `aggregateExternalSteps`).
3. **`delete()`** — ограничен ли только записями своего приложения (используется в `deleteManualRecord`).

Код написан согласно спеке. Проверка выполняется пользователем на эмуляторе/устройстве
с Health Connect Toolbox. Компиляция и отсутствие ошибок = подтверждение.

## Следующий шаг

Фаза 3 (`docs/phase3_confirmation_ux_spec.md`) — UX-поток подтверждения значения:
5 состояний (`loading` / `missing` / `autoUnconfirmed` / `manualEntryActive` / `manualConfirmed`),
точка входа через тап по графику, блокировка только карточки метрики при `missing`.

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