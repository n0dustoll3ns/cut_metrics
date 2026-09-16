import 'package:collection/collection.dart';
import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/expenditure_day.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/nutrition_day.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/recommendation_engine.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:cut_metrics/domain/sleep_analyzer.dart';
import 'package:cut_metrics/domain/sleep_day.dart';
import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/domain/weekly_energy_stats.dart';
import 'package:cut_metrics/repo/health_permissions.dart';
import 'package:cut_metrics/repo/health_repository.dart';
import 'package:cut_metrics/services/debug_log.dart';
import 'package:cut_metrics/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Результат резолюции значения для конкретной даты и метрики.
///
/// Обёртка над значением + источник, возвращаемая [DashboardViewModel.getResolvedValue].
/// UI использует это для определения состояния карточки метрики (Фаза 3, секция 3;
/// Фаза 6 — [sourcePackage] для беджа и решений по источнику).
class ResolvedValue<T> {
  final T value;
  final DataSource source;

  /// Пакет приложения-источника итогового значения (Фаза 6, C.2):
  /// наш пакет для ручного ввода, пакет внешнего приложения для внешних данных.
  final String? sourcePackage;

  const ResolvedValue({required this.value, required this.source, this.sourcePackage});

  @override
  String toString() =>
      'ResolvedValue(value: $value, source: $source, sourcePackage: $sourcePackage)';
}

/// ViewModel дашборда: состояние UI + оркестрация репозитория и процессора.
///
/// БЕЗ бизнес-логики — только:
/// 1. Загрузка данных из репозитория (батчем).
/// 2. Резолюция через [HealthDataProcessor] (чистая синхронная функция).
/// 3. Хранение in-memory кешей (_weightCache, _stepsCache, _emaCache).
/// 4. Методы подтверждения значения (Фаза 3): submit/cancel/getResolvedValue.
///
/// Сессионный in-memory кэш — остаётся (оптимизация в рамках одного запуска,
/// не персистентность, см. `systemPatterns.md` → "Без локального кэша/БД").
class DashboardViewModel extends ChangeNotifier {
  final HealthRepository _repo;
  final HealthDataProcessor _processor;
  final Health? _health;

  /// Переопределяемая проверка разрешений Health Connect (для тестов).
  ///
  /// Если `null` — используется [checkAndRequestPermissions] (продакшн-режим).
  /// Позволяет покрыть юнит-тестами ветку «разрешения не выданы», которая
  /// иначе требует реального Health Connect на устройстве.
  final Future<bool> Function(Health health)? _permissionCheck;

  /// Переопределяемая тихая проверка разрешений БЕЗ системного диалога
  /// (для тестов). Если `null` — используется `Health.hasPermissions`.
  /// Задействуется в [recheckPermissions] при возврате в приложение.
  final Future<bool?> Function(Health health)? _permissionStatusCheck;

  // ─── Фаза 5: сон, настройки, саммари ─────────────────────────────────────────

  final SleepAnalyzer _sleepAnalyzer = SleepAnalyzer();

  /// Персистентные настройки (целевой темп, уровень активности, дата саммари).
  ///
  /// Опционален: в тестах без `shared_preferences` используются дефолты из
  /// [RecommendationConfig] / [ActivityLevel.level1], записи настроек нет.
  final SettingsService? _settings;

  double _targetPace = RecommendationConfig.defaultTargetPacePercent;

  // ─── Фаза 7: питание, расход, профиль ────────────────────────────────────────

  /// Профиль расхода из настроек (A.2) — оверрайды компонентов.
  ExpenditureProfile _energyProfile = const ExpenditureProfile();

  /// Рост из HC `HEIGHT` (last-wins за 365 дней) — префилл, пока
  /// пользователь не ввёл рост вручную (`_energyProfile.heightCm == null`).
  double? _hcHeightCm;

  /// Сырые точки питания за сессию — для перерезолюции при смене
  /// решений/выбора источника без похода в HC (B.4/C.4 Фазы 6).
  List<HealthDataPoint> _rawNutritionPoints = const [];

  /// Сырые точки HC BASAL за сессию.
  List<HealthDataPoint> _rawBasalPoints = const [];

  // ─── Фаза 6, B/C: сырые точки сессии + решения/выбор источников ─────────────

  /// Сырые точки веса за сессию (последний `load()`/`_reloadDate`).
  ///
  /// Нужны для перерезолюции при смене решения/выбора источника — без
  /// нового похода в Health Connect («Список найденных источников» тоже
  /// строится по ним). Сессионный кеш, не персистентность (Фаза 4).
  List<HealthDataPoint> _rawWeightPoints = const [];

  /// Сырые точки шагов за сессию.
  List<HealthDataPoint> _rawStepsPoints = const [];

  /// Решения по источникам на метрику: пакет → решение (B.1).
  final Map<MetricType, Map<String, ConfirmDecision>> _decisions = {};

  /// Выбранный источник на метрику: «Авто» или приложение (C.1).
  final Map<MetricType, SourceSelection> _selections = {};

  // ─── Публичное состояние ────────────────────────────────────────────────────

  DateTime get start => _start;
  DateTime get end => _end;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// `true` — разрешения Health Connect не выданы, последний [load] прерван.
  ///
  /// UI (экран «Сегодня») показывает баннер с кнопкой перехода в системные
  /// настройки приложения (2026-08-26). Сбрасывается в начале каждого [load].
  bool get permissionsDenied => _permissionsDenied;

  /// Список точек веса для UI (отсортирован по дате, в диапазоне start–end).
  List<WeightDay> get weightData => _weightData;
  List<WeightDay> get emaData => _emaData;
  List<StepsDay> get stepsData => _stepsData;

  /// Целевой темп, %/нед (слайдер в Настройках).
  double get targetPace => _targetPace;

  /// Профиль расхода из настроек (Фаза 7, A.2).
  ExpenditureProfile get energyProfile => _energyProfile;

  /// Рост: ручной ввод (`energy_height_cm`) или префилл из HC `HEIGHT`.
  double? get effectiveHeightCm => _energyProfile.heightCm ?? _hcHeightCm;

  /// Текущая длина диапазона Тренда в днях (для подсветки сегмента).
  int get rangeDays => _rangeDays;

  // ─── Приватное состояние ────────────────────────────────────────────────────

  DateTime _start;
  DateTime _end;
  bool _isLoading = false;
  String? _error;

  /// Разрешения не выданы — load() прерван на шаге permissions.
  /// Поднимается вместе с [_error], см. геттер [permissionsDenied].
  bool _permissionsDenied = false;

  /// Длина текущего диапазона Тренда в днях (7/30/90).
  int _rangeDays = RecommendationConfig.todayChartDays;

  // Кеши обработанных данных (все загруженные, не только видимый диапазон).
  //
  // ⚠️ Сессионные in-memory кеши — НЕ персистентные. При каждом cold start
  // (перезапуск приложения) очищаются и заполняются заново из Health Connect
  // в [load]. Осознанное решение (Фаза 4) — локальная БД не используется,
  // Health Connect остаётся единственным источником истины.
  final Map<DateKey, WeightDay> _weightCache = {};
  final Map<DateKey, StepsDay> _stepsCache = {};

  /// Питание по дням после резолюции (Фаза 7).
  final Map<DateKey, NutritionDay> _nutritionCache = {};

  /// HC BASAL по дням, ккал/день (last-wins; Фаза 7).
  final Map<DateKey, double> _basalCache = {};

  /// Расход по дням (там, где рассчитан BMR; Фаза 7). Пересчитывается при
  /// загрузке/перерезолюции/смене профиля расхода.
  final Map<DateKey, ExpenditureDay> _expenditureCache = {};

  /// Ночи сна с данными (пустые ночи не попадают — С4).
  final Map<DateKey, SleepDay> _sleepCache = {};
  Map<DateKey, WeightDay> _emaCache = {};

  // Данные для UI (отфильтрованы по диапазону start–end).
  List<WeightDay> _weightData = [];
  List<WeightDay> _emaData = [];
  List<StepsDay> _stepsData = [];

  /// Период EMA зависит от длины выбранного диапазона.
  int get _emaPeriod {
    final days = _end.difference(_start).inDays;
    if (days >= 20) return 10;
    if (days >= 10) return 5;
    return 3;
  }

  DashboardViewModel({
    required HealthRepository repository,
    required HealthDataProcessor processor,
    Health? health,
    SettingsService? settingsService,
    Future<bool> Function(Health health)? permissionCheck,
    Future<bool?> Function(Health health)? permissionStatusCheck,
    bool autoLoad = true,
  }) : _repo = repository,
       _processor = processor,
       _health = health,
       _permissionCheck = permissionCheck,
       _permissionStatusCheck = permissionStatusCheck,
       _settings = settingsService,
       _start = DateTime.now().subtract(
         const Duration(days: RecommendationConfig.todayChartDays - 1),
       ),
       _end = DateTime.now() {
    if (autoLoad) load();
  }

  // ─── Загрузка данных ────────────────────────────────────────────────────────

  /// Загружает данные из Health Connect в кеши, пересчитывает EMA, обновляет UI.
  ///
  /// Полный пересчёт при каждой загрузке — см. `systemPatterns.md` → "Без локального
  /// кэша/БД". Сессионный in-memory кэш остаётся, но при load() обновляется из HC.
  ///
  /// Если [_health] == null (тесты с моком), шаг permissions пропускается.
  Future<void> load() async {
    final stopwatch = Stopwatch()..start();
    DebugLog.instance.log('vm', 'load: старт');
    _isLoading = true;
    _error = null;
    _permissionsDenied = false;
    notifyListeners();

    try {
      // Настройки Фазы 5 (целевой темп), Фазы 7 (профиль расхода) и Фазы 6
      // (решения по источникам, выбор источника на метрику).
      if (_settings != null) {
        _targetPace = await _settings.loadTargetPace();
        _energyProfile = await _settings.loadEnergyProfile();
        for (final metric in MetricType.values) {
          _decisions[metric] = await _settings.loadSourceDecisions(metric);
          _selections[metric] = await _settings.loadSourceSelection(metric);
        }
      }

      // Permissions — только если есть реальный Health (не тест с моком).
      if (_health != null) {
        final granted = await (_permissionCheck ?? checkAndRequestPermissions)(
          _health,
        );
        if (!granted) {
          _permissionsDenied = true;
          _error =
              'Нет разрешений для доступа к Health Connect. Откройте настройки '
              'приложения и разрешите доступ к данным о здоровье.';
          DebugLog.instance.warn(
            'vm',
            'load: permissions не выданы — загрузка прервана',
          );
          return;
        }
      }

      // Грузим за maxTrendDays (90) — движку рекомендаций нужен вес за окно
      // независимо от того, какой сегмент Тренда смотрит пользователь.
      final loadStart = DateTime.now().subtract(
        const Duration(days: RecommendationConfig.maxTrendDays - 1),
      );

      // Загружаем сырые точки веса батчем за весь диапазон.
      final weightPoints = await _repo.fetchRawData(
        types: const [HealthDataType.WEIGHT],
        startDate: loadStart,
        endDate: _end,
      );

      // Загружаем сырые точки шагов одним батчевым запросом (Фаза 6, A2:
      // aggregate-API удалены, резолюция «один источник на день» — по точкам).
      final stepsPoints = await _repo.fetchRawData(
        types: const [HealthDataType.STEPS],
        startDate: loadStart,
        endDate: _end,
      );

      // Сон: с запасом −1 день — ночь, начавшаяся в 23:00, относится к
      // следующему дню сна (правило С3).
      final sleepPoints = await _repo.fetchRawData(
        types: kSleepTypes,
        startDate: loadStart.subtract(const Duration(days: 1)),
        endDate: _end,
      );

      // Фаза 7 (§7): питание и BASAL — за 90 дней в общий батч.
      final nutritionPoints = await _repo.fetchRawData(
        types: const [HealthDataType.NUTRITION],
        startDate: loadStart,
        endDate: _end,
      );
      final basalPoints = await _repo.fetchRawData(
        types: const [HealthDataType.BASAL_ENERGY_BURNED],
        startDate: loadStart,
        endDate: _end,
      );

      // Рост — за 365 дней (меняется медленно), last-wins → префилл профиля
      // (только пока пользователь не ввёл рост вручную).
      final heightPoints = await _repo.fetchRawData(
        types: const [HealthDataType.HEIGHT],
        startDate: DateTime.now().subtract(
          const Duration(days: ExpenditureConfig.heightLoadDays),
        ),
        endDate: _end,
      );

      // Сырые точки сессии — для перерезолюции при смене решений/выбора.
      _rawWeightPoints = weightPoints;
      _rawStepsPoints = stepsPoints;
      _rawNutritionPoints = nutritionPoints;
      _rawBasalPoints = basalPoints;
      _hcHeightCm = _processor.resolveHeight(heightPoints);

      // Резолюция приоритета источников (Tier 1 → Tier 2) с решениями и
      // выбором источников (Фаза 6, B/C).
      final weightResolved = _processor.resolveWeightForAllDates(
        weightPoints,
        decisions: _decisions[MetricType.weight] ?? const {},
        selection: _selections[MetricType.weight] ?? const SourceSelection.auto(),
      );
      final stepsResolved = _processor.resolveStepsForAllDates(
        stepsPoints,
        decisions: _decisions[MetricType.steps] ?? const {},
        selection: _selections[MetricType.steps] ?? const SourceSelection.auto(),
        onWarn: (message) => DebugLog.instance.warn('vm', message),
      );
      final sleepResolved = _sleepAnalyzer.analyze(
        rawPoints: sleepPoints,
        rangeStart: loadStart,
        rangeEnd: _end,
      );

      // Обновляем кеши.
      _weightCache
        ..clear()
        ..addAll(weightResolved);
      _stepsCache
        ..clear()
        ..addAll(stepsResolved);
      _sleepCache
        ..clear()
        ..addAll(sleepResolved);

      // Фаза 7: питание + BASAL + расход.
      _refreshNutritionAndExpenditure();

      // EMA пересчитывается по актуальному кешу весов.
      _emaCache = _processor.computeEma(_weightCache, _emaPeriod);

      DebugLog.instance.log(
        'vm',
        'load: резолюция — вес ${weightPoints.length} тчк → '
            '${_weightCache.length} дн., шаги ${stepsPoints.length} тчк → '
            '${_stepsCache.length} дн., сон ${sleepPoints.length} тчк → '
            '${_sleepCache.length} ночей, питание ${nutritionPoints.length} тчк → '
            '${_nutritionCache.length} дн., BASAL ${basalPoints.length} тчк → '
            '${_basalCache.length} дн., расход ${_expenditureCache.length} дн., '
            'рост HC ${_hcHeightCm?.toStringAsFixed(0) ?? '—'} см, '
            'EMA ${_emaCache.length} тчк',
      );

      _refreshChartData();
    } catch (e) {
      _error = 'Ошибка загрузки: $e';
      DebugLog.instance.error('vm', 'load: $e');
      debugPrint('DashboardViewModel.load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      DebugLog.instance.log(
        'vm',
        'load: готово за ${stopwatch.elapsedMilliseconds} мс',
      );
    }
  }

  /// Тихая перепроверка разрешений БЕЗ системного диалога.
  ///
  /// Вызывается при возврате в приложение (`AppLifecycleState.resumed`,
  /// observer в `main.dart`), если [permissionsDenied]: пользователь мог
  /// выдать права в системных настройках. Права выданы → [load] (баннер
  /// исчезнет, данные загрузятся). Не выданы → ничего не делает, баннер
  /// остаётся. Исключения глушатся — фоновая перепроверка не должна
  /// ломать UI.
  Future<void> recheckPermissions() async {
    if (!_permissionsDenied || _health == null) return;
    try {
      final granted = await (_permissionStatusCheck ?? _hasAllPermissions)(
        _health,
      );
      DebugLog.instance.log('vm', 'recheckPermissions → $granted');
      if (granted == true) {
        await load();
      }
    } catch (e) {
      DebugLog.instance.error('vm', 'recheckPermissions: $e');
    }
  }

  /// Продакшн-режим тихой проверки: РАЗДЕЛЬНЫЕ вызовы `hasPermissions` по
  /// каждому типу (вес, шаги, 10 стадий сна, питание) — без системного
  /// диалога (в отличие от `checkAndRequestPermissions`). Значение каждого
  /// пермишена пишется в DebugLog тегом `perm`, см.
  /// `checkPermissionsPerType` в `health_permissions.dart` (2026-08-28).
  Future<bool?> _hasAllPermissions(Health health) async {
    final perType = await checkPermissionsPerType(health);
    return allGranted(perType);
  }

  /// Перезагружает данные для одной даты после submit/cancel.
  ///
  /// Не очищает весь кеш — только обновляет значение для конкретной даты,
  /// затем пересчитывает EMA (для веса — по всему кешу, т.к. EMA скользящее).
  /// Сырые точки даты в сессионном списке заменяются свежими — перерезолюция
  /// при смене решений остаётся консистентной.
  Future<void> _reloadDate(DateKey date, MetricType type) async {
    final dayPoints = await _repo.fetchRawData(
      types: [_healthDataTypeOf(type)],
      startDate: date.startOfDay,
      endDate: date.endOfDay,
    );
    if (type == MetricType.weight) {
      _rawWeightPoints = _replacePointsForDate(_rawWeightPoints, date, dayPoints);
      final resolved = _processor.resolveWeightForDate(
        date,
        _rawWeightPoints,
        decisions: _decisions[MetricType.weight] ?? const {},
        selection: _selections[MetricType.weight] ?? const SourceSelection.auto(),
      );
      if (resolved != null) {
        _weightCache[date] = resolved;
      } else {
        _weightCache.remove(date);
      }
      // EMA пересчитывается по всему кешу весов — правка даты влияет на все даты после.
      _emaCache = _processor.computeEma(_weightCache, _emaPeriod);
      // Вес на дату участвует в расходе (шаги/Mifflin) — пересчитываем.
      _refreshExpenditure();
    } else if (type == MetricType.nutrition) {
      // «Итог дня» (A.7): замена точек дня + перерезолюция питания.
      _rawNutritionPoints = _replacePointsForDate(_rawNutritionPoints, date, dayPoints);
      _refreshNutrition();
    } else {
      // Шаги — не накопительны, пересчёт EMA не нужен.
      _rawStepsPoints = _replacePointsForDate(_rawStepsPoints, date, dayPoints);
      final resolved = _processor.resolveStepsForDate(
        date,
        _rawStepsPoints,
        decisions: _decisions[MetricType.steps] ?? const {},
        selection: _selections[MetricType.steps] ?? const SourceSelection.auto(),
      );
      if (resolved != null) {
        _stepsCache[date] = resolved;
      } else {
        _stepsCache.remove(date);
      }
      // Шаги дня входят в расход — пересчитываем.
      _refreshExpenditure();
    }
    _refreshChartData();
    notifyListeners();
  }

  /// Заменяет в списке сырых точек все точки даты [date] на [dayPoints].
  static List<HealthDataPoint> _replacePointsForDate(
    List<HealthDataPoint> points,
    DateKey date,
    List<HealthDataPoint> dayPoints,
  ) {
    return [
      ...points.where((p) => DateKey(p.dateFrom) != date),
      ...dayPoints,
    ];
  }

  static HealthDataType _healthDataTypeOf(MetricType type) => switch (type) {
    MetricType.weight => HealthDataType.WEIGHT,
    MetricType.steps => HealthDataType.STEPS,
    MetricType.nutrition => HealthDataType.NUTRITION,
  };

  /// Фильтрует кеши по текущему диапазону дат для UI.
  void _refreshChartData() {
    bool inRange(DateKey k) => k.value.isInsideInterval(_start, _end);

    _weightData = _weightCache.entries
        .where((e) => inRange(e.key))
        .map((e) => e.value)
        .sorted((a, b) => a.date.compareTo(b.date));
    _emaData = _emaCache.entries
        .where((e) => inRange(e.key))
        .map((e) => e.value)
        .sorted((a, b) => a.date.compareTo(b.date));
    _stepsData = _stepsCache.entries
        .where((e) => inRange(e.key))
        .map((e) => e.value)
        .sorted((a, b) => a.date.compareTo(b.date));
  }

  // ─── API Фазы 5: диапазоны, средние, саммари, настройки ──────────────────────

  /// Меняет длину диапазона Тренда (7/30/90 дней).
  ///
  /// Данные уже загружены за [RecommendationConfig.maxTrendDays] при [load],
  /// поэтому смена в пределах 90 дней — только пересортировка кеша, без похода
  /// в Health Connect.
  void setRange(int days) {
    _rangeDays = days;
    _start = DateTime.now().subtract(Duration(days: days - 1));
    _end = DateTime.now();
    _refreshChartData();
    notifyListeners();
  }

  /// Среднесуточный сон за диапазон, ч — только по ночам с данными (С4:
  /// пустые ночи исключаются из знаменателя). `null` — нет ни одной ночи.
  double? get avgSleepHours {
    final nights = _sleepCache.values
        .where((n) => n.date.value.isInsideInterval(_start, _end))
        .toList();
    if (nights.isEmpty) return null;
    final total = nights.map((n) => n.total).reduce((a, b) => a + b);
    return total / nights.length;
  }

  /// Среднесуточные шаги за диапазон — по дням с записями, БЕЗ «сегодня»
  /// (A.8: подсчёт дня ещё не завершён). `null` — нет данных.
  int? get avgSteps {
    final today = DateKey(DateTime.now());
    final days = _stepsCache.entries
        .where((e) => e.key.value.isInsideInterval(_start, _end) && e.key != today)
        .toList();
    if (days.isEmpty) return null;
    final total = days.map((e) => e.value.steps).reduce((a, b) => a + b);
    return (total / days.length).round();
  }

  /// Дней с питанием в диапазоне, кроме «сегодня» (покрытие «по N дн.»).
  int get intakeDaysInRange {
    final today = DateKey(DateTime.now());
    return _nutritionCache.keys
        .where((k) => k.value.isInsideInterval(_start, _end) && k != today)
        .length;
  }

  /// Среднесуточный приход, ккал — по дням с данными, без «сегодня» (A.8).
  /// `null` — ни одного дня с питанием.
  double? get avgCaloriesIn {
    final today = DateKey(DateTime.now());
    final days = _nutritionCache.entries
        .where((e) => e.key.value.isInsideInterval(_start, _end) && e.key != today)
        .toList();
    if (days.isEmpty) return null;
    final total = days.map((e) => e.value.calories).reduce((a, b) => a + b);
    return total / days.length;
  }

  /// Средние макросы (Б/Ж/У, г/день) — по дням с приходом, без «сегодня»;
  /// день без макроса считается нулём (решение пользователя 2026-09-14).
  /// `null` — ни одного дня с питанием.
  ({double? protein, double? fat, double? carbs})? get avgMacros {
    final today = DateKey(DateTime.now());
    final days = _nutritionCache.entries
        .where((e) => e.key.value.isInsideInterval(_start, _end) && e.key != today)
        .toList();
    if (days.isEmpty) return null;
    final n = days.length;
    return (
      protein: days.map((e) => e.value.protein ?? 0).reduce((a, b) => a + b) / n,
      fat: days.map((e) => e.value.fat ?? 0).reduce((a, b) => a + b) / n,
      carbs: days.map((e) => e.value.carbs ?? 0).reduce((a, b) => a + b) / n,
    );
  }

  /// Среднесуточный расход, ккал — по дням, где рассчитан BMR, без «сегодня»
  /// (полный расход из 4 компонентов; «РАСХОД» на Тренде). `null` — нет.
  double? get avgExpenditure {
    final today = DateKey(DateTime.now());
    final days = _expenditureCache.entries
        .where((e) => e.key.value.isInsideInterval(_start, _end) && e.key != today)
        .toList();
    if (days.isEmpty) return null;
    final total = days.map((e) => e.value.total).reduce((a, b) => a + b);
    return total / days.length;
  }

  /// Дней с расходом в диапазоне, кроме «сегодня» (покрытие «по N дн.»).
  int get expenditureDaysInRange {
    final today = DateKey(DateTime.now());
    return _expenditureCache.keys
        .where((k) => k.value.isInsideInterval(_start, _end) && k != today)
        .length;
  }

  /// Самый свежой резолвленный вес из кеша (для формул калорий), или `null`.
  double? _latestWeight() {
    if (_weightCache.isEmpty) return null;
    final sorted = _weightCache.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return sorted.last.weight;
  }

  /// Последний резолвленный вес (публично — редактор оверрайда шагов
  /// пересчитывает «ккал/1000 шагов» в коэффициент, §0 п. 14).
  double? get latestWeightKg => _latestWeight();

  /// Питание для даты (после резолюции) — карточка «Питание» (B.2).
  NutritionDay? nutritionFor(DateKey date) => _nutritionCache[date];

  /// Расход для даты (если BMR рассчитан) — «Итого сегодня» в Настройках,
  /// строка «Расход ≈ N» в карточке питания.
  ExpenditureDay? expenditureFor(DateKey date) => _expenditureCache[date];

  /// Энергобаланс по дням диапазона (для графика A2): только дни, где есть
  /// И питание, И расход — баланс без расхода не считается (A.4 п.4).
  /// «Сегодня» исключён — сбор данных за день ещё не завершён (правило
  /// вывода «за вчера», 2026-09-16; вес — единственное исключение).
  List<EnergyBalanceDay> get balanceData {
    final today = DateKey(DateTime.now());
    final result = <EnergyBalanceDay>[];
    for (final entry in _nutritionCache.entries) {
      if (entry.key == today) continue;
      if (!entry.key.value.isInsideInterval(_start, _end)) continue;
      final out = _expenditureCache[entry.key];
      if (out == null) continue;
      result.add(EnergyBalanceDay(intake: entry.value, out: out));
    }
    return result..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Дней в диапазоне до «сегодня» (невключительно) без данных питания —
  /// примечание под графиком баланса («Дней без данных питания: N»).
  int get daysWithoutNutritionInRange {
    final today = DateKey(DateTime.now());
    var count = 0;
    for (var d = _start.onlyDate; !d.isAfter(_end.onlyDate); d = d.add(const Duration(days: 1))) {
      if (!d.isBefore(today.value)) break;
      if (!_nutritionCache.containsKey(DateKey(d))) count++;
    }
    return count;
  }

  /// Целевой дефицит, ккал/день: `вес × темп % × 11` (A.3) по последнему
  /// резолвленному весу. `null` — веса нет.
  double? get targetDeficitKcalPerDay {
    final weight = _latestWeight();
    if (weight == null) return null;
    return ExpenditureConfig.targetDeficitKcalPerDay(weight, _targetPace);
  }

  /// Подсказка профиля (B.5): BMR не рассчитан ни одним способом для «сегодня»
  /// (нет HC-BASAL на день, профиль неполон, ручного оверрайда нет).
  bool get needsProfileHint => expenditureFor(DateKey(DateTime.now())) == null;

  /// Источник BMR «сегодня» — для подписи строки «Базальный (BMR)» в
  /// настройках (B.4): вручную / HC / формула / не рассчитан.
  BmrSource get bmrSourceForToday {
    final today = DateKey(DateTime.now());
    if (_energyProfile.bmrMode == BmrMode.manual &&
        _energyProfile.bmrManualKcal != null &&
        _energyProfile.bmrManualKcal! > 0) {
      return BmrSource.manual;
    }
    if (_basalCache[today] != null && _basalCache[today]! > 0) {
      return BmrSource.healthConnect;
    }
    if (_expenditureCache.containsKey(today)) return BmrSource.mifflin;
    return BmrSource.none;
  }

  /// «Ккал на 1000 шагов» для UI оверрайда шагов (§0 п. 14): коэффициент ×
  /// последний резолвленный вес × 1000. `null` — веса нет.
  double? get kcalPer1000Steps {
    final weight = _latestWeight();
    if (weight == null) return null;
    return _energyProfile.stepsKcalPerKgPerStep * weight * 1000;
  }

  /// Меняет профиль расхода (Настройки, мгновенное применение): персистит и
  /// пересчитывает расход из уже загруженных кешей — без похода в HC.
  Future<void> setEnergyProfile(ExpenditureProfile profile) async {
    DebugLog.instance.log('vm', 'профиль расхода обновлён: $profile');
    _energyProfile = profile;
    await _settings?.saveEnergyProfile(profile);
    _refreshExpenditure();
    notifyListeners();
  }

  /// Энергостаты за скользящее окно (C.1) — пересчёт при каждом вызове,
  /// как [computeWeeklySummary] (U3). `null` — дней с приходом < 2.
  WeeklyEnergyStats? computeWeeklyEnergyStats() => computeEnergyStats(
        nutritionCache: _nutritionCache,
        expenditureCache: _expenditureCache,
        today: DateTime.now(),
      );

  // ─── Фаза 7: перерезолюция питания/BASAL/расхода из кешей сессии ───────────

  /// Перерезолвляет BASAL + питание + расход (после load / смены роста из HC).
  void _refreshNutritionAndExpenditure() {
    _basalCache
      ..clear()
      ..addAll(_processor.resolveBasalForAllDates(_rawBasalPoints));
    _refreshNutrition();
    _refreshExpenditure();
  }

  /// Перерезолвляет питание (смена решений/выбора источника/«Итога дня»).
  void _refreshNutrition() {
    final nutritionResolved = _processor.resolveNutritionForAllDates(
      _rawNutritionPoints,
      decisions: _decisions[MetricType.nutrition] ?? const {},
      selection: _selections[MetricType.nutrition] ?? const SourceSelection.auto(),
      onWarn: (message) => DebugLog.instance.warn('vm', message),
    );
    _nutritionCache
      ..clear()
      ..addAll(nutritionResolved);
  }

  /// Пересчитывает расход по дням для загруженного диапазона (90 дней) с
  /// HC-префиллом роста, пока нет ручного ввода.
  void _refreshExpenditure() {
    final profile = _energyProfile.heightCm != null
        ? _energyProfile
        : _energyProfile.copyWith(heightCm: _hcHeightCm);
    final resolved = _processor.computeExpenditures(
      weightCache: _weightCache,
      stepsCache: _stepsCache,
      basalCache: _basalCache,
      profile: profile,
      start: DateKey(DateTime.now().subtract(
        const Duration(days: ExpenditureConfig.nutritionLoadDays - 1),
      )),
      end: DateKey(DateTime.now()),
    );
    _expenditureCache
      ..clear()
      ..addAll(resolved);
  }

  /// Сглаженный вес «на сегодня» — последняя точка EMA-линии дашборда.
  ///
  /// Это то самое большое число на вкладке «Сегодня» (аннотация макета:
  /// «большое число на экране это и есть последняя точка сглаженной линии»).
  /// `null` — данных нет.
  double? get smoothedWeightToday =>
      _emaData.isEmpty ? null : _emaData.last.weight;

  /// Пересчитывает еженедельное саммари за скользящие 7 дней (U3: при каждом
  /// вызове, без еженедельного гейта).
  ///
  /// `null` — недостаточно данных: в окне меньше
  /// [RecommendationConfig.minWeightPointsInWindow] сырых точек веса.
  ///
  /// Фаза 7, C.2: движку передаются энергостаты — при их наличии тексты v2
  /// с конкретными ккал; при `null` (<2 дней с приходом) — тексты Фазы 5.
  WeeklySummary? computeWeeklySummary() {
    final engineEma = _processor.computeEma(
      _weightCache,
      RecommendationConfig.engineEmaPeriod,
    );
    return RecommendationEngine.compute(
      weightCache: _weightCache,
      emaCache: engineEma,
      today: DateTime.now(),
      targetPacePercent: _targetPace,
      energyStats: computeWeeklyEnergyStats(),
    );
  }

  /// Фиксирует факт показа саммари (хранится, но не гейтит показ — U3).
  Future<void> markSummaryShown() async {
    await _settings?.saveLastSummaryShownDate(DateTime.now());
  }

  /// Устанавливает целевой темп (слайдер в Настройках, мгновенное применение).
  Future<void> setTargetPace(double value) async {
    _targetPace = value;
    await _settings?.saveTargetPace(value);
    notifyListeners();
  }

  // ─── API Фазы 3: подтверждение значения (секция 8 спеки) ─────────────────────

  /// Уже резолвленное значение + источник для конкретной даты.
  ///
  /// Новых обращений к Health Connect не требует — значение из in-memory кеша.
  /// Возвращает `null`, если данных нет (→ состояние `missing`/`sourceRefused`
  /// в UI, различает их [isSourceRefused]).
  ResolvedValue<num>? getResolvedValue(DateKey date, MetricType type) {
    switch (type) {
      case MetricType.weight:
        final w = _weightCache[date];
        if (w == null) return null;
        return ResolvedValue(
          value: w.weight,
          source: w.source,
          sourcePackage: w.sourcePackage,
        );
      case MetricType.steps:
        final s = _stepsCache[date];
        if (s == null) return null;
        return ResolvedValue(
          value: s.steps,
          source: s.source,
          sourcePackage: s.sourcePackage,
        );
      case MetricType.nutrition:
        // Для питания карточка работает с [nutritionFor] (макросы нужны
        // целиком); этот кейс — полнота switch + калории как значение.
        final n = _nutritionCache[date];
        if (n == null) return null;
        return ResolvedValue(
          value: n.calories,
          source: n.source,
          sourcePackage: n.sourcePackage,
        );
    }
  }

  /// Пишет ручное значение (Tier 1) в Health Connect, обновляет кеш,
  /// при необходимости пересчитывает EMA, notifyListeners().
  ///
  /// Возвращает `true` при успехе; `false` — запись не удалась (ошибка уже
  /// в [error] и DebugLog, карточка показывает снекбар — A1.3).
  Future<bool> submitManualValue(
    DateKey date,
    MetricType type,
    num value,
  ) async {
    DebugLog.instance.log('vm', 'submit $date ${type.name} = $value');
    try {
      await _repo.writeManualRecord(date, type, value);
      await _reloadDate(date, type);
      return true;
    } catch (e) {
      _error = 'Не удалось сохранить: $e';
      DebugLog.instance.error('vm', 'submit $date ${type.name} = $value: $e');
      debugPrint('DashboardViewModel.submitManualValue error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Удаляет ручную запись (Tier 1), откатывает на Tier 2/missing,
  /// обновляет кеш, пересчитывает EMA при необходимости, notifyListeners().
  ///
  /// Возвращает `true` при успехе, `false` — удаление не удалось.
  Future<bool> cancelManualValue(DateKey date, MetricType type) async {
    DebugLog.instance.log('vm', 'cancel $date ${type.name}');
    try {
      await _repo.deleteManualRecord(date, type);
      await _reloadDate(date, type);
      return true;
    } catch (e) {
      _error = 'Не удалось отменить: $e';
      DebugLog.instance.error('vm', 'cancel $date ${type.name}: $e');
      debugPrint('DashboardViewModel.cancelManualValue error: $e');
      notifyListeners();
      return false;
    }
  }

  // ─── Фаза 7, A.7: ручной «Итог дня» ─────────────────────────────────────────

  /// Пишет ручной «Итог дня» (Tier 1, NUTRITION) в Health Connect, обновляет
  /// кеш питания. `true` при успехе, `false` — запись не удалась (ошибка уже
  /// в [error] и DebugLog, карточка показывает снекбар — паттерн A1.3 Фазы 6).
  Future<bool> submitManualNutrition(
    DateKey date, {
    required double calories,
    double? protein,
    double? fat,
    double? carbs,
  }) async {
    DebugLog.instance.log(
      'vm',
      'submit итог дня $date = ${calories.toStringAsFixed(0)} ккал',
    );
    try {
      await _repo.writeManualNutrition(
        date,
        calories: calories,
        protein: protein,
        fat: fat,
        carbs: carbs,
      );
      await _reloadDate(date, MetricType.nutrition);
      return true;
    } catch (e) {
      _error = 'Не удалось сохранить итог дня: $e';
      DebugLog.instance.error('vm', 'submit итог дня $date: $e');
      debugPrint('DashboardViewModel.submitManualNutrition error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Удаляет ручной «Итог дня» — откат на внешние данные/missing.
  /// `true` при успехе, `false` — удаление не удалось.
  Future<bool> cancelManualNutrition(DateKey date) async {
    DebugLog.instance.log('vm', 'cancel итог дня $date');
    try {
      await _repo.deleteManualNutrition(date);
      await _reloadDate(date, MetricType.nutrition);
      return true;
    } catch (e) {
      _error = 'Не удалось удалить итог дня: $e';
      DebugLog.instance.error('vm', 'cancel итог дня $date: $e');
      debugPrint('DashboardViewModel.cancelManualNutrition error: $e');
      notifyListeners();
      return false;
    }
  }

  // ─── Фаза 6, B: кеш подтверждений «Ок / Не ок» ───────────────────────────────

  /// Текущее решение для пары (метрика, источник). Отсутствие решения —
  /// [ConfirmDecision.none] («спрашивать»).
  ConfirmDecision decisionFor(MetricType metric, String package) =>
      (_decisions[metric] ?? const {})[package] ?? ConfirmDecision.none;

  /// Текущий выбор источника для метрики (дефолт «Авто»).
  SourceSelection selectionFor(MetricType metric) =>
      _selections[metric] ?? const SourceSelection.auto();

  /// Источник «доверяем» (карточка тихая): решение `confirmed` ИЛИ источник
  /// выбран явно (выбор = доверие, C.4).
  bool isSourceTrusted(MetricType metric, String? package) {
    if (package == null || package.isEmpty) return false;
    if ((_selections[metric] ?? const SourceSelection.auto()).package == package) {
      return true;
    }
    return decisionFor(metric, package) == ConfirmDecision.confirmed;
  }

  /// Все ли источники с данными за дату отклонены (состояние `sourceRefused`)?
  ///
  /// `true` — внешние точки за дату есть, но каждое их приложение получило
  /// решение `refused` (резолюция вернёт `null` → карточка переходит в режим
  /// ручного ввода). Ручные (Tier 1) точки не учитываются — они всегда свои.
  bool isSourceRefused(DateKey date, MetricType type) {
    final dayPoints = _rawPointsFor(type)
        .where((p) => DateKey(p.dateFrom) == date)
        .toList();
    final external = dayPoints.where((p) => !_processor.isOurPoint(p)).toList();
    if (external.isEmpty) return false;
    return external.every(
      (p) => decisionFor(type, HealthDataProcessor.sourcePackageOf(p)) ==
          ConfirmDecision.refused,
    );
  }

  /// «Ок» — доверяем источнику для метрики (B.2).
  ///
  /// Пишет ТОЛЬКО решение (данные не пишет), персистит, перерезолвляет кеши
  /// из сырых точек сессии — без обращений к репозиторию. Карточка становится
  /// тихой (`autoConfirmed`).
  Future<void> confirmSource(MetricType metric, String package) async {
    DebugLog.instance.log(
      'vm',
      'Ок: ${metric.name} ← $package (доверяем источнику)',
    );
    _decisions.putIfAbsent(metric, () => {})[package] = ConfirmDecision.confirmed;
    await _settings?.saveSourceDecision(metric, package, ConfirmDecision.confirmed);
    _reResolveFromRaw();
  }

  /// «Не ок» — постоянный отказ источника для метрики (B.3).
  ///
  /// Точки источника исключаются из резолюции (каждый день — ручной ввод),
  /// решение персистится и меняется в Настройках или в карточке («⋯»).
  Future<void> refuseSource(MetricType metric, String package) async {
    DebugLog.instance.log(
      'vm',
      'Не ок: ${metric.name} ← $package (отклоняем источник)',
    );
    _decisions.putIfAbsent(metric, () => {})[package] = ConfirmDecision.refused;
    await _settings?.saveSourceDecision(metric, package, ConfirmDecision.refused);
    _reResolveFromRaw();
  }

  /// Сбрасывает решение по источнику («Сбросить решение» в подэкране
  /// источников). Карточка снова спрашивает «Ок/Не ок».
  Future<void> resetDecision(MetricType metric, String package) async {
    DebugLog.instance.log(
      'vm',
      'сброс решения: ${metric.name} ← $package (снова спрашиваем)',
    );
    _decisions[metric]?.remove(package);
    await _settings?.saveSourceDecision(metric, package, ConfirmDecision.none);
    _reResolveFromRaw();
  }

  // ─── Фаза 6, C: выбор источника на метрику ──────────────────────────────────

  /// Найденные внешние источники для метрики — по сырым точкам сессии,
  /// без дополнительных запросов к Health Connect (C.1).
  List<String> availableSources(MetricType metric) =>
      _processor.externalSources(_rawPointsFor(metric));

  /// Меняет выбранный источник (в т.ч. обратно на «Авто») — персистит и
  /// перерезолвляет кеши из сырых точек сессии, без похода в Health Connect.
  Future<void> setSourceSelection(MetricType metric, SourceSelection selection) async {
    DebugLog.instance.log(
      'vm',
      'выбор источника ${metric.name}: '
      '${selection.isAuto ? 'Авто' : selection.package}',
    );
    _selections[metric] = selection;
    await _settings?.saveSourceSelection(metric, selection);
    _reResolveFromRaw();
  }

  // ─── Фаза 6: перерезолюция из сырых точек сессии ────────────────────────────

  List<HealthDataPoint> _rawPointsFor(MetricType metric) => switch (metric) {
    MetricType.weight => _rawWeightPoints,
    MetricType.steps => _rawStepsPoints,
    MetricType.nutrition => _rawNutritionPoints,
  };

  /// Перерезолвляет кеши веса/шагов/питания из сырых точек сессии с текущими
  /// решениями/выбором источника. Вызывается при confirm/refuse/reset/setSelection —
  /// данные уже в памяти, обращений к репозиторию нет (B.4/C.4). Вместе с
  /// питанием пересчитывается расход (шаги тех же дней не меняются, но
  /// перерезолюция единого пайплайна проще и дешевле похода в HC).
  void _reResolveFromRaw() {
    final weightResolved = _processor.resolveWeightForAllDates(
      _rawWeightPoints,
      decisions: _decisions[MetricType.weight] ?? const {},
      selection: _selections[MetricType.weight] ?? const SourceSelection.auto(),
    );
    final stepsResolved = _processor.resolveStepsForAllDates(
      _rawStepsPoints,
      decisions: _decisions[MetricType.steps] ?? const {},
      selection: _selections[MetricType.steps] ?? const SourceSelection.auto(),
      onWarn: (message) => DebugLog.instance.warn('vm', message),
    );
    _weightCache
      ..clear()
      ..addAll(weightResolved);
    _stepsCache
      ..clear()
      ..addAll(stepsResolved);
    _refreshNutrition();
    _refreshExpenditure();
    _emaCache = _processor.computeEma(_weightCache, _emaPeriod);
    _refreshChartData();
    notifyListeners();
  }
}
