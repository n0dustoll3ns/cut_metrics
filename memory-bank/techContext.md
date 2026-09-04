# Tech Context — Cut Metrics

## Стек

- Flutter, целевая платформа — Android (iOS в перспективе, не сейчас)
- Health Connect через пакет `health` — основной источник данных, чтение и запись
- `provider` — `ChangeNotifierProvider`, `context.select`, `context.read`
- `fl_chart` — `LineChart` (вес+EMA), `BarChart` (шаги, питание, сон)
- `collection` — `.sorted()` на списках
- `intl` — `DateFormat.yMd()`

Полная карта файлов и структуры — `docs/cut_metrics_project_map.md`.

## Ограничения сборочной машины (важно для сборки)

Рабочая машина — общая (RDP): ~24 ГБ RAM + pagefile 32 ГБ, свободный commit-лимит в рабочее
время может падать до ~1–2 ГБ. Поэтому в `android/gradle.properties` занижены JVM-аппетиты
Gradle (`-Xmx3G`, `MaxMetaspaceSize=1G`, `workers.max=2`). Значения из шаблона (`-Xmx8G`,
metaspace 4G) исчерпывали память: `flutter build apk` падал с `System.OutOfMemoryException`
в `flutter\bin\internal\update_engine_version.ps1` ("Unable to determine engine version") →
`:app:compileFlutterBuildRelease` failed. Починено 2026-08-18, сборка успешна
(`build\app\outputs\flutter-apk\app-release.apk`, ~49 МБ).

## Дизайн-система

Токены и компоненты — `docs/cutmetrics-design-system.html` (открыть в браузере или прочитать как
HTML/CSS). Ключевое:
- Шрифты: Space Grotesk (числа, tabular-nums), Inter (текст), Space Mono (подписи, uppercase)
- 6 брендовых цветов: Instrument Grey, Deep Ink, Noise Grey, Signal Cobalt, Steady Green, Alert Rust
- Статус-беджи — точка-индикатор + текст Deep Ink на бледной подложке, НЕ сплошная заливка
  (обоснование — контраст AA, см. сам файл, секция "Цвет")
- 8pt spacing grid, инструментальные (не мягкие) радиусы

Не изобретать новые hex-значения — всё нужное для текущих фаз уже есть в файле (см. Фазу 5,
часть B, для примера расширения `.badge`).

## Технические риски, требующие проверки на реальном устройстве/эмуляторе (не гадать)

Первые три — из `docs/phase2_repository_write_spec.md`, четвёртый — из `docs/phase4_no_cache_spec_v2.md`:

1. **`sourceId` в пакете `health`** — действительно ли равен package name приложения на Android,
   а не внутреннему UUID. Нужно для `hasManualRecord` (Фаза 1/2).
2. **`getTotalStepsInInterval`** — использует ли нативный Health Connect `aggregate()` с
   приоритетом источников, или суммирует сырые записи в Dart (тогда не решает проблему
   двойного счёта шагов). Проверять через Health Connect Toolbox с двумя источниками на одну дату.
3. **`delete()` в пакете `health`** — действительно ли ограничен только записями своего
   приложения (платформенное ограничение) — проверить перед тем, как полагаться на это в UX
   "отменить правку" (Фаза 3).
4. **`getHealthIntervalDataFromTypes`** (Фаза 4) — использует ли тот же нативный `aggregate()` с
   приоритетом источников, что и `getTotalStepsInInterval`, или суммирует сырые записи.
   Используется в `aggregateExternalStepsForRange` для батчевой агрегации шагов. Проверять так же:
   два источника на одну дату, результат должен быть одним значением по приоритету, а не суммой.

Если что-то из этого не подтверждено экспериментально — не считать решённым, даже если код
скомпилировался и заработал на первый взгляд.

Статус (обновлено 2026-09-02 по итогам A0-лога `memory-bank/debug.log` + анализа исходников
пакета `health` 13.3.1/13.3.2 в pub-cache):

- №1 — **решён**: на Android `sourceId` ВСЕГДА пустой — в пакете `health` значение
  захардкожено (`HealthDataConverter.createBaseRecord`: `"source_id" to ""`), заполнен
  только у sleep-сессий. Реальный пакет приложения (в т.ч. наш `com.example.cut_metrics`)
  приходит в **`sourceName`** = `metadata.dataOrigin.packageName`. Следствие для Фазы 6:
  Tier 1 и список источников строить по `sourceName`.
- №4 — **подтверждён**: `getHealthIntervalDataFromTypes(interval: 1440)` вернул
  «0 дней с шагами» при 24 587 сырых точках STEPS. Решение Фазы 6 (A2) — резолюция шагов
  по сырым точкам «один источник на день», оба aggregate-API уходят из архитектуры
  (вместе с этим закрывается и №2 — `getTotalStepsInInterval` больше не используется).
- №2 — **закрыт архитектурно** (Фаза 6, A2, 2026-09-03): оба aggregate-метода удалены
  из контракта репозитория; шаги резолвляются по сырым точкам в `HealthDataProcessor`
  («один источник на день», максимальная сумма за день среди неотклонённых источников).
- №3 — остаётся непроверенным на устройстве (платформенное ограничение `delete()`
  своими записями; проверить при UX «отменить правку» в задании №2).
