# Cut Metrics — Фаза 2: Repository — чтение и запись

> ТЗ для разработки. Реализует интерфейсный контракт, зафиксированный в
> `cut_metrics_phase1_data_model_spec.md`, разделы 6–7.
> Статус: к реализации. Зависит от Фазы 1 (модели `WeightDay`/`StepsDay` с полем `source`).

---

## 1. Контекст и цель

Фаза 1 определила алгоритм резолюции и интерфейс `HealthRepository` с методами `hasManualRecord`,
`writeManualRecord`, `deleteManualRecord`, `aggregateExternalSteps` — но не их реализацию.
Эта фаза реализует эти методы поверх пакета `health` (используется в проекте, см.
`cut_metrics_project_map.md`).

---

## 2. Скоуп

- Вес и шаги: запись, удаление, проверка наличия ручной записи, агрегация внешних источников.
- Sleep и Nutrition остаются read-only, как сейчас — не трогаем.

---

## 3. Permissions / изменения в онбординге

Сейчас `checkAndRequestPermissions(types)` в `repo/health.dart` запрашивает права без разделения
read/write. Нужно расширить: для `WEIGHT` и `STEPS` — `HealthDataAccess.READ_WRITE`, для остальных
типов — `HealthDataAccess.READ`, как раньше.

```dart
final types = [
  HealthDataType.WEIGHT, HealthDataType.STEPS,
  ...sleepTypes, HealthDataType.NUTRITION,
];
final permissions = [
  HealthDataAccess.READ_WRITE, // WEIGHT
  HealthDataAccess.READ_WRITE, // STEPS
  ...sleepTypes.map((_) => HealthDataAccess.READ),
  HealthDataAccess.READ,       // NUTRITION
];
await health.requestAuthorization(types, permissions: permissions);
```

**UX-побочный эффект:** системный диалог Health Connect покажет пункт "запись" для веса и шагов —
это дополнительная строка в списке разрешений при первом онбординге. Health Connect также требует
rationale-экран перед показом системного диалога — если он уже есть в проекте, текст стоит дополнить
объяснением, зачем нужна запись (ручная корректировка данных).

---

## 4. Реализация методов контракта

### `writeManualRecord`

```dart
Future<void> writeManualRecord(DateKey date, MetricType type, num value) async {
  final healthType = _toHealthDataType(type); // WEIGHT | STEPS
  final isSteps = type == MetricType.steps;
  await health.writeHealthData(
    value: value.toDouble(),
    type: healthType,
    startTime: date.startOfDay,
    endTime: isSteps ? date.endOfDay : date.startOfDay, // шаги — суточный тотал, вес — точка
    recordingMethod: RecordingMethod.manual,
  );
}
```

### `hasManualRecord`

```dart
Future<bool> hasManualRecord(DateKey date, MetricType type) async {
  final points = await health.getHealthDataFromTypes(
    date.startOfDay, date.endOfDay, [_toHealthDataType(type)],
  );
  return points.any((p) => p.sourceId == _ownPackageId);
}
```

> ⚠️ **Проверить экспериментально перед реализацией дальнейшей логики:** действительно ли
> `sourceId` на Android равен package name нашего приложения (а не внутреннему UUID установки).
> Пакет `health` начал заполнять `sourceId`/`sourceName` относительно недавно — поведение стоит
> подтвердить на реальном устройстве. Если `sourceId` ненадёжен — резервный вариант: фильтровать по
> `recordingMethod == RecordingMethod.manual`, но это менее точный признак (любое стороннее
> приложение тоже может писать данные вручную, и мы бы приняли их запись за свою).

### `deleteManualRecord`

```dart
Future<void> deleteManualRecord(DateKey date, MetricType type) async {
  await health.delete(
    type: _toHealthDataType(type),
    startTime: date.startOfDay,
    endTime: date.endOfDay,
  );
}
```

> ⚠️ **Критично проверить перед релизом.** Судя по модели разрешений Health Connect, приложение
> может удалять только те записи, которые само создало — но это ограничение платформы, а не
> задокументированное явно поведение пакета `health`. **Обязательный тест перед сдачей фазы:**
> через Health Connect Toolbox записать "внешнюю" запись на дату + свою ручную через приложение,
> вызвать `deleteManualRecord`, убедиться, что внешняя запись осталась нетронутой. Без этой
> проверки есть риск случайно стереть синхронизированные данные пользователя из других
> приложений/устройств при нажатии "отменить правку".

### `aggregateExternalSteps`

```dart
Future<int?> aggregateExternalSteps(DateKey date) async {
  return await health.getTotalStepsInInterval(date.startOfDay, date.endOfDay);
}
```

> ⚠️ **Критично проверить перед реализацией дальнейшей логики.** Из документации пакета неясно,
> вызывает ли `getTotalStepsInInterval` нативный Health Connect `aggregate()` (с дедупликацией по
> приоритету источников — то, что нужно) или просто суммирует сырые записи на стороне Dart
> (тогда проблема двойного счёта, которую решает вся эта фаза, никуда не денется).
> **Обязательный тест:** через Toolbox создать 2 источника шагов с разными значениями на одну дату,
> вызвать метод, проверить — результат должен быть **одним** значением по приоритету, а не суммой.
> Если пакет суммирует — потребуется отдельная задача: нативный вызов Health Connect `aggregate()`
> через platform channel в обход пакета `health`.

---

## 5. Изменения в `MockHealthRepository`

- Генерировать тестовые точки с разными `sourceId`/`recordingMethod` (свой пакет / внешний) —
  нужно для юнит-тестов резолюции из Фазы 1.
- Реализовать `write`/`delete`/`aggregate` как in-memory `Map`-заглушки — без реального Health
  Connect юнит-тесты Фазы 1 не смогут проверить сценарии "записали → resolve вернул manual →
  удалили → resolve вернул external".

---

## 6. Обработка ошибок

`writeHealthData`/`delete` могут вернуть `false` или бросить исключение при отсутствии прав
или недоступности Health Connect (не установлен / отключён пользователем). Методы репозитория
должны либо возвращать `bool success`, либо бросать типизированное исключение — ViewModel должен
иметь возможность отловить это и показать пользователю фидбек (не молчаливый сбой). Сам UI такого
фидбека — задача Фазы 3, здесь фиксируется только то, что репозиторий не должен глушить ошибку.

---

## 7. Definition of Done

- [ ] `checkAndRequestPermissions` запрашивает `READ_WRITE` для Weight/Steps, `READ` — для остального
- [ ] `writeManualRecord`, `hasManualRecord`, `deleteManualRecord`, `aggregateExternalSteps`
      реализованы согласно контракту Фазы 1
- [ ] **Подтверждено на реальном устройстве/эмуляторе:** `deleteManualRecord` не затрагивает записи
      других источников на ту же дату
- [ ] **Подтверждено:** `aggregateExternalSteps` не суммирует несколько источников (или есть
      fallback через нативный `aggregate()`, если пакет `health` суммирует сам)
- [ ] `MockHealthRepository` поддерживает write/delete/aggregate и разные `sourceId` для тестов
- [ ] Ошибки записи/удаления не глушатся молча — репозиторий пробрасывает их наверх
