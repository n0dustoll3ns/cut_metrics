# Active Context — Cut Metrics

> Обновляется по ходу работы (сообщением "update memory bank").

## Текущий фокус

Реализация фаз 1–5 по спекам в `docs/`, строго в этом порядке (см. `systemPatterns.md`,
"Порядок фаз реализации").

**Фаза 1 завершена** (2026-08-06): модель данных (`DataSource`, `WeightDay`, `StepsDay`),
резолюция источников (`HealthDataProcessor`), контракт репозитория, `MockHealthRepository`,
25 тестов — все зелёные, `flutter analyze` чист.

## Следующий шаг

Фаза 2 (`docs/phase2_repository_write_spec.md`) — реализация `HealthRepository`:
чтение/запись в Health Connect, `hasManualRecord`, `writeManualRecord`,
`deleteManualRecord`, `aggregateExternalSteps`. Контракт зафиксирован в Фазе 1
(`lib/repo/health_repository.dart`).

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