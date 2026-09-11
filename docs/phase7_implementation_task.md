# Cut Metrics — Фаза 7, задание: реализация «Питание и энергобаланс»

> ТЗ для разработки в СЛЕДУЮЩЕМ чате. Источник истины — спека `docs/phase7_nutrition_energy_spec.md`
> (включая §0 пп. 13–14 от 2026-09-11). Дизайн-референс — `docs/design-system.html` §05
> («Энергобаланс — Фаза 7», «Карточка „Питание“ — Фаза 7», тёмные превью в §06) и макеты
> `docs/screen-today-graph-summary-settings.html` (все четыре экрана + тёмный фрейм + аннотации
> «Фаза 7 — питание и энергобаланс»). Паттерны Фаз 1–6 — `memory-bank/systemPatterns.md`.
> Порядок: **A (домен + репозиторий + мок + тесты) → B (экраны) → C (движок + саммари)**;
> промежуточная сборка APK после A, финальная после C.

## 0. Решения пользователя (все подтверждены в чате)

Пп. 1–12 — спека §0 (2026-09-10). Дополнительно 2026-09-11:

13. **Дельта рекомендаций v2 динамическая**: `delta = вес × |целевой − фактический темп (п.п.)| × 11`,
    коридор **50–300 ккал/день**, округление до 10; `{intakeNew} = {intake} ∓ {delta}`; скобка в
    шаблоне тоже динамическая: «(−{delta} ккал)» / «(+{delta} ккал)».
14. **Оверрайд «Шаги»**: хранится коэффициент `energy_steps_kcal_per_kg_per_step`; в UI вводится
    и показывается «ккал на 1000 шагов» = коэффициент × последний резолвленный вес × 1000;
    отображаемое число пересчитывается при изменении веса, коэффициент — нет.

Допущения (зафиксированы при дизайне 2026-09-11, спеке не противоречат):

- `WeeklyEnergyStats`: `avgIntake` — по дням с приходом; `avgExpenditure` — по дням с расходом;
  `avgBalance` — только по дням, где есть И приход, И расход (следует из A.4 п.4 «баланс за день
  не считается»); покрытие «по N из M дней» — по приходу.
- Подсказка профиля (B.5) — на «Сегодня» под карточкой «Питание».
- График энергобаланса — на «Тренде» под графиком веса, реагирует на сегмент Неделя/Месяц/
  3 мес, включает столбец «сегодня» (A.8).

## 1. Дизайн-решения (2026-09-11, зафиксированы в HTML — сверяться при реализации)

- **График энергобаланса (A2)**: нулевая линия — ink-muted 1px; целевая линия дефицита — signal
  1.5px, пунктир 5-4, подпись «цель −N» (N = вес × темп % × 11, округление до 10); дефицит —
  столбцы вниз steady, профицит — вверх alert; столбцы rx≈2, ширина min(14, 0.6 × шаг); масштаб —
  ноль, целевая и все балансы всегда в кадре; ось дат — механика WeightChart A3 без изменений;
  тултип в 2 строки: «17 июл» / «Приход 2 150 · Расход 2 680 · Баланс −530»; дни без прихода —
  без столбца; примечание «Дней без данных питания: N» (скрыто при N = 0); заголовок
  «Энергобаланс · ккал/день» + легенда (Дефицит / Профицит / Цель).
- **Карточка «Питание»**: autoUnconfirmed — значение + бедж «Из MyFitnessPal» + крупные
  «Ок / Не ок», под числом mono-строка «Расход ≈ 2 400 · Баланс −250» (только если расход
  рассчитан); manualConfirmed — «Итог дня: 2 100 ккал · Б 150 · Ж 70 · У 220» + бедж «Ручной
  ввод» (signal-точка на signal-tint) + «Изменить / Удалить»; missing — текст + кнопка «Ввести
  итог»; форма — 4 поля (ккал шире) + «Сохранить»; autoConfirmed — компакт + меню «⋯»
  (как Фаза 6). Все 7 состояний — в аннотациях макета и `design-system.html` §05.
- **Подсказка профиля**: signal-tint карточка «Рассчитаем ваш расход» — пока BMR не рассчитан
  ни одним способом (нет HC-BASAL и профиль неполон); тап → блок «Профиль расхода» в Настройках.
- **Среднесуточные на «Тренде»**: сетка ячеек как сейчас; «АКТИВНОСТЬ» → «РАСХОД»; вторая
  строка через разделитель: ПРИХОД + Б/Ж/У; под каждой энерго-ячейкой покрытие «по N дн.»
  (mono 9.5); примечание «Сегодня не учитывается — день ещё не завершён».
- **Саммари**: карточка «Энергобаланс недели» после основной — 4 строки label/value: средний
  приход (с покрытием «по 6 из 7 дней»), средний расход, средний баланс (отрицательный —
  steady), «Ожидаемый темп ≈ −0.48 кг/нед».
- **Настройки**: блок «Профиль расхода» — сегмент Мужской/Женский, поля «Год рождения» и
  «Рост, см» (префилл из HC), hint про то, что HC не хранит пол/возраст; блок «Расход
  калорий» — 4 строки (имя + mono-источник + значение + «⋯»), редактор силовых (степпер
  частоты 0–7, поле длительности, сегмент Умеренная/Тяжёлая, поле «своя ккал/сессия»), строка
  «Итого сегодня ≈ N ккал/день» (signal) = сумма 4 компонентов за сегодня. Порядок блоков:
  Тема → Источники HC → Целевой вес → Целевой темп → **Профиль расхода** → **Расход
  калорий** → Подписка → Health-сервис (в макете подписка/HC внизу — свериться с кодом).
- Новых hex-значений нет — только существующие роли `CMThemeColors`.

## 2. Часть A — домен, репозиторий, мок, тесты (спека §3)

Новые файлы: `lib/domain/nutrition_day.dart`, `lib/domain/expenditure_day.dart`,
`lib/domain/expenditure_config.dart`, `lib/domain/weekly_energy_stats.dart` (чистый Dart).

- **A.1** `NutritionDay {DateKey date; double calories; double? protein, fat, carbs;
  DataSource source; String? sourcePackage}` + `==`/`hashCode` (образец — `WeightDay`).
  `MetricType` + значение `nutrition` — механика решений/выбора источника Фазы 6
  переиспользуется автоматически (ключи `src_decision.nutrition.<pkg>`,
  `src_selection.nutrition`; циклы по `MetricType.values` уже есть в VM/настройках).
- **A.2** Профиль расхода — `SettingsService`, ключи с префиксом `energy_` по таблице A.2
  спеки: `energy_sex` (m/f), `energy_birth_year`, `energy_height_cm`, `energy_bmr_mode`
  (auto/manual), `energy_bmr_manual_kcal`, `energy_steps_kcal_per_kg_per_step` (0.0004),
  `energy_training_freq_per_week` (0–7, дефолт 0), `energy_training_duration_min` (60),
  `energy_training_intensity` (moderate/heavy), `energy_training_kcal_per_session` (null),
  `energy_household_kcal` (200).
- **A.3** `ExpenditureConfig` — ВСЕ константы Фазы 7 в одном месте (паттерн
  `RecommendationConfig`): Mifflin М/Ж (`10W+6.25H−5A+5` / `−161`), нетто-шаги 0.0004,
  MET 3.5/6.0 (нетто −1), бытовой 200, целевой дефицит = вес × темп% × 11, дельта
  рекомендаций = вес × |цель−факт| × 11 (коридор 50–300, округление до 10 — §0 п. 13),
  тексты-шаблоны v2 ({balance}/{actual}/{target}/{intake}/{intakeNew}/{delta}).
- **A.4** Каскад BMR на день: manual-оверрайд → HC `BASAL_ENERGY_BURNED` (значение в
  ккал/день, last-wins за день) → Mifflin (пол+возраст+рост+вес на дату; возраст = год
  даты − birth_year) → null («расход —», баланс за день не считается).
- **A.5** `ExpenditureDay {date, bmrKcal, stepsKcal, trainingKcal, householdKcal}` +
  `get total`; `EnergyBalanceDay {NutritionDay intake; ExpenditureDay out}` +
  `get balance`; `==`/`hashCode` у обоих. Вес «на дату» — последняя резолвленная запись
  веса ≤ дата (префикс-проход по сортированному кешу). День без шагов = 0 шагов (текущая
  семантика). День без веса: шаги-компонент = 0, Mifflin невозможен, BMR из HC работает.
  Считается синхронно в `HealthDataProcessor` из резолвленных кешей, без хранения сырых точек.
- **A.6** Резолюция питания «один источник на день» в `HealthDataProcessor` (паттерн Фазы 6
  A2/C; отличие — правило авто): источник с **наибольшим числом дней, имеющих записи**, в
  загруженном диапазоне; при равенстве — больше записей; при равенстве — большая сумма
  калорий. Ценность дня = сумма калорий и макросов ТОЛЬКО победившего источника (записи
  внутри дня суммируются). Tier 1 «Итог дня» всегда побеждает для своей даты; refused-фильтр
  и выбор источника — как у шагов. День без записей = нет данных (НЕ 0) → исключается из
  средних, показывается покрытие «по N из M дней». Несколько источников в дне → warn (`onWarn`).
- **A.7** Контракт репозитория: `writeManualNutrition(DateKey date, {required double calories,
  double? protein, double? fat, double? carbs})`, `hasManualNutrition(DateKey)`,
  `deleteManualNutrition(DateKey)` (контракт + impl + мок). Реализация — `Health.writeMeal`:
  `name: 'Итог дня'` (HC требует непустое имя), `mealType: MealType.UNKNOWN`,
  startTime/endTime = `DateKey.startOfDay`/`endOfDay`, `recordingMethod:
  RecordingMethod.manual`; идемпотентность — delete-then-write наших NutritionRecord за дату
  (детект своих записей по `sourceName`, аналог A1.1 Фазы 6). `writeManualRecord` веса/шагов
  не менять.
- **A.8** Правило «сегодня»: `Today = DateKey(DateTime.now())` исключается из средних
  прихода/расхода/баланса, энергостатов саммари и `avgSteps`; вес за сегодня — валидный день.
  График баланса включает столбец «сегодня» без спец-пометки.
- **A.9** Мок: NUTRITION — 3–6 приёмов/день (ккал + Б/Ж/У, источник «MyFitnessPal»,
  `com.myfitnesspal.android`), 1–2 дня без записей; BASAL — 1 точка/день ~1670 ккал
  («Samsung Health»); HEIGHT — 178 см в пределах года. Детерминированность.

DoD части A — чек-лист спеки A.9; промежуточная сборка APK после A.

## 3. Часть B — экраны (спека §4 + дизайн-решения §1)

- `lib/ui/energy_balance_chart.dart` — НОВЫЙ, fl_chart `BarChart`:
  - один стэк-столбец на день = баланс (приход − расход); отрицательные — вниз от нулевой
    линии (отрицательные `BarChartRodData` fl_chart поддерживает — проверить на установленной
    версии; если нет — НЕ сдвигать ось, а спросить пользователя);
  - цвет по знаку: дефицит `steady`, профицит `alert`; целевая линия — `ExtraLinesData`
    `HorizontalLine(y: −target, color: signal, dashed)`; нулевая — `HorizontalLine(y: 0,
    color: inkMuted)`;
  - ось дат — вынести/переиспользовать механику `WeightChart` A3 (числа, «1 АВГ», ≤8 меток,
    сетка на границе месяца); тултип в 2 строки: дата / «Приход · Расход · Баланс»;
  - данные — `vm.balanceData` за текущий `rangeDays` (дни без прихода — столбца нет);
    примечание «Дней без данных питания: N» под графиком (скрыто при 0).
- `lib/ui/nutrition_card.dart` — НОВЫЙ, 7 состояний по образцу `MetricCard` (Фаза 6 B.4);
  форма «Итог дня»: ккал (обязательно) + Б/Ж/У г (опционально), «Сохранить» → bool-возврат +
  снекбар ошибки (паттерн A1.3 Фазы 6); «Изменить»/«Удалить» — VM-методы с bool-возвратами;
  меню «⋯» в autoConfirmed — как у метрик; под числом «Расход ≈ N · Баланс ±N» (если расход
  рассчитан).
- `lib/ui/today_screen.dart`: `NutritionCard` после кнопки саммари; ниже — подсказка профиля
  (signal-tint «Рассчитаем ваш расход»), пока BMR недоступен (нет HC-BASAL и профиль неполон);
  ErrorBox/PermissionsBanner не трогать.
- `lib/ui/trend_screen.dart`: `EnergyBalanceChart` под `WeightChart` (реагирует на сегмент);
  «Среднесуточные»: «АКТИВНОСТЬ» → «РАСХОД» (`vm.avgExpenditure`), вторая строка через
  разделитель: «ПРИХОД» (`vm.avgCaloriesIn`) + «Б/Ж/У» (`vm.avgMacros`), покрытие «по N дн.»,
  примечание «Сегодня не учитывается»; `_AvgMetric` переиспользовать; `vm.avgCaloriesPerDay`
  (шаги×вес×0.0005 + уровень) удалить.
- `lib/ui/summary_screen.dart`: после основной карточки — «Энергобаланс недели» из
  `vm.computeWeeklyEnergyStats()` (4 строки label/value; отрицательный баланс — steady);
  при null — блок скрыт.
- `lib/ui/settings_screen.dart`: блоки «Профиль расхода» и «Расход калорий» (дизайн §1);
  УДАЛИТЬ блок «Уровень активности» и импорт `activity_level.dart`; «Итого сегодня» =
  `vm.expenditureFor(today).total`; оверрайд «Шаги» — ввод «ккал/1000 шагов», пересчёт в
  коэффициент (§0 п. 14).
- Источники: `_SourcesBlock` (тернарник `metric == MetricType.weight ? 'Вес' : 'Шаги'`) →
  map {weight: Вес, steps: Шаги, nutrition: Питание}; `SourceSettingsScreen` — заголовок и
  данные для nutrition; решения «Ок/Не ок» для питания подхватятся автоматически.
- Все цвета через `context.cmColors` (новых hex нет); проверить обе темы.

## 4. Часть C — саммари и движок (спека §5)

- `lib/domain/weekly_energy_stats.dart` (чистый Dart): окно = последние 7 дней ИСКЛЮЧАЯ
  сегодня; поля `avgIntake`, `intakeDays` (0–6), `avgExpenditure`, `avgBalance`,
  `expectedKgPerWeek` (= avgBalance × 7 / 7700); знаменатели — §0 этого документа; при
  `intakeDays < 2` → null (энергоблок скрыт, движок — по текстам Фазы 5).
- `RecommendationEngine.compute`: опциональный параметр `WeeklyEnergyStats? energyStats`
  (+ вес на «сегодня» для дельты). Без energyStats — тексты Фазы 5 ДОСЛОВНО (регрессионный
  тест обязателен). С energyStats — шаблоны v2 из `ExpenditureConfig`, подстановка
  {balance}/{intake}/{intakeNew}/{delta} (§0 п. 13).
- VM: `computeWeeklyEnergyStats()` (пересчёт при смене решений/источника/итога дня);
  энергоблок саммари; DebugLog: тег `vm` — ввод/правка/удаление итога, «Ок/Не ок» питания;
  тег `repo` — `sourceName` точек NUTRITION/BASAL.

## 5. Разрешения (12 → 14 типов) — спека §6

`lib/repo/health_permissions.dart`: группа «Питание» NUTRITION → `READ_WRITE`; новые группы
«Базальный метаболизм» `[BASAL_ENERGY_BURNED]` READ и «Рост» `[HEIGHT]` READ. Регрессионный
тест «каждый тип из `kPermissionGroups` есть в `dataTypeKeysAndroid`» — на 14 типов.
Существующие пользователи получат один пакетный диалог (тихий предчек уже реализован).

## 6. Загрузка данных — спека §7

`DashboardViewModel.load`: `fetchRawData(NUTRITION)` + `fetchRawData(BASAL_ENERGY_BURNED)`
за 90 дней — в существующий батч; `fetchRawData(HEIGHT)` за 365 дней, last-wins → префилл
`energy_height_cm` (если пользователь не вводил вручную). Сырые точки сессии
`_rawNutritionPoints`; кеши `_nutritionCache`/`_basalCache`; геттеры `nutritionData`,
`expenditureFor(DateKey)`, `balanceData`, `avgCaloriesIn`, `avgExpenditure`, `avgMacros`,
`targetDeficitKcalPerDay`; `_reResolveFromRaw()` + питание; `_reloadDate` — для «Итог дня».

## 7. Миграции — спека §8

- `lib/domain/activity_level.dart` УДАЛИТЬ; убрать использования (`settings_screen`,
  `trend_screen`, VM `avgCaloriesPerDay`, `SettingsService.load/saveActivityLevel`);
  ключ `activity_level` больше не читается (игнор, без ошибок).
- `RecommendationConfig.stepsKcalPerKgPerStep` (0.0005) удалить — теперь
  `ExpenditureConfig.stepsKcalPerKgPerStep` (0.0004).
- NUTRITION READ→READ_WRITE — тихий предчек увидит и покажет один диалог (уже реализовано).

## 8. Тесты (ориентир +30 к 148)

Резолюция питания (авто-покрытие дней > записей > суммы; Tier 1 всегда побеждает;
refused/selection; «день без записей ≠ 0»); каскад BMR (4 уровня; неполный профиль;
last-wins за день); формулы (Mifflin М/Ж; нетто 0.0004; MET 3.5/6.0/своя-сессия; бытовой
200; целевой дефицит ×11; дельта — коридор 50–300, округление до 10); `ExpenditureDay` с
весом «на дату» (до первой записи веса); средние с исключением «сегодня»; покрытие «по N
дням»; `WeeklyEnergyStats` (окно/покрытие/null при <2 дней); движок v2 (регресс текстов
Фазы 5 дословно + подстановка чисел, все 3 статуса); VM (загрузка NUTRITION/BASAL/HEIGHT,
перерезолюция из сырых точек, запись/правка/удаление итога, bool-возвраты); permissions
(14 типов; группы ⊆ dataTypeKeysAndroid); мок (детерминированность); обновить тесты,
затронутые удалением `ActivityLevel`.

## 9. Техриски — проверка на устройстве пользователем (спека §9, до закрытия фазы)

R1 `writeMeal` roundtrip (итог создаётся, читается back с нашим `sourceName` и макросами);
R2 BASAL реального ПО (пишут ли, частота, разумность ккал/день, last-wins); R3 NUTRITION
реальных трекеров (гранулярность, макросы, 2 источника → один источник, НЕ сумма); R4
HEIGHT за год → корректный префилл; R5 `delete()` своими NutritionRecord (повторный ввод
итога не плодит дубли).

## 10. Карта изменений (файлы)

| Файл | Изменение |
|---|---|
| `lib/domain/nutrition_day.dart` | НОВЫЙ: `NutritionDay` |
| `lib/domain/expenditure_day.dart` | НОВЫЙ: `ExpenditureDay`, `EnergyBalanceDay` |
| `lib/domain/expenditure_config.dart` | НОВЫЙ: константы A.3 + дефолты + шаблоны v2 |
| `lib/domain/weekly_energy_stats.dart` | НОВЫЙ: `WeeklyEnergyStats` |
| `lib/domain/metric_type.dart` | + `nutrition` |
| `lib/domain/activity_level.dart` | УДАЛИТЬ |
| `lib/domain/health_data_processor.dart` | резолюция питания (авто-покрытие), каскад BMR, `ExpenditureDay`/`EnergyBalanceDay`, внешние источники питания |
| `lib/domain/recommendation_config.dart` | − `stepsKcalPerKgPerStep`; тексты v2 → в `ExpenditureConfig` |
| `lib/domain/recommendation_engine.dart` | v2: `energyStats?`, подстановка чисел, регресс старых текстов |
| `lib/repo/health_repository.dart` + impl + mock | `writeManualNutrition`/`hasManualNutrition`/`deleteManualNutrition` |
| `lib/repo/health_permissions.dart` | 14 типов; NUTRITION READ_WRITE; +BASAL, +HEIGHT |
| `lib/services/settings_service.dart` | профиль расхода `energy_*`; − activity_level |
| `lib/viewmodel/dashboard_view_model.dart` | загрузка NUTRITION/BASAL/HEIGHT; кеши и геттеры; итог дня (bool); energy stats; − ActivityLevel |
| `lib/ui/energy_balance_chart.dart` | НОВЫЙ: график A2 |
| `lib/ui/nutrition_card.dart` | НОВЫЙ: карточка «Питание», 7 состояний |
| `lib/ui/today_screen.dart` | карточка питания + подсказка профиля |
| `lib/ui/trend_screen.dart` | график баланса; среднесуточные РАСХОД/ПРИХОД/БЖУ; − АКТИВНОСТЬ |
| `lib/ui/summary_screen.dart` | карточка «Энергобаланс недели» |
| `lib/ui/settings_screen.dart` | «Профиль расхода» + «Расход калорий»; − «Уровень активности»; лейблы источников на 3 метрики |
| `test/*` | новые + обновление существующих |

## 11. DoD и сборки

- Часть A: чек-лист спеки A.9; APK после A (мок гоняет все экраны ещё без UI-новинок).
- Часть B: чек-лист спеки B.6; обе темы (CMThemeColors).
- Часть C: чек-лист спеки C.4; финальный APK.
- Общее: все тесты зелёные (ориентир ~178), `flutter analyze` = базлайн (4 info / 0 errors),
  проверки раздела 9 выполнены пользователем на устройстве.

## 12. Документация по ходу

- README: структура lib/ (новые файлы), статус Фазы 7.
- memory-bank: activeContext/progress по итогам; systemPatterns — новые паттерны (резолюция
  питания «по покрытию дней», каскад BMR, правило «сегодня» для средних).
- Спеку не переписывать; найденное противоречие — сначала вопрос пользователю.