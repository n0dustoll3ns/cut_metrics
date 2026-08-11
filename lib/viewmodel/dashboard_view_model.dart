import 'package:collection/collection.dart';
import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/steps_day.dart';
import 'package:cut_metrics/domain/weight_day.dart';
import 'package:cut_metrics/repo/health_permissions.dart';
import 'package:cut_metrics/repo/health_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

/// Результат резолюции значения для конкретной даты и метрики.
///
/// Обёртка над значением + источник, возвращаемая [DashboardViewModel.getResolvedValue].
/// UI использует это для определения состояния карточки метрики (Фаза 3, секция 3).
class ResolvedValue<T> {
  final T value;
  final DataSource source;

  const ResolvedValue({required this.value, required this.source});

  @override
  String toString() => 'ResolvedValue(value: $value, source: $source)';
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

  // ─── Публичное состояние ────────────────────────────────────────────────────

  DateTime get start => _start;
  DateTime get end => _end;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Список точек веса для UI (отсортирован по дате, в диапазоне start–end).
  List<WeightDay> get weightData => _weightData;
  List<WeightDay> get emaData => _emaData;
  List<StepsDay> get stepsData => _stepsData;

  // ─── Приватное состояние ────────────────────────────────────────────────────

  final DateTime _start;
  final DateTime _end;
  bool _isLoading = false;
  String? _error;

  // Кеши обработанных данных (все загруженные, не только видимый диапазон).
  final Map<DateKey, WeightDay> _weightCache = {};
  final Map<DateKey, StepsDay> _stepsCache = {};
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
    bool autoLoad = true,
    // ignore: prefer_initializing_formals
  })  : _repo = repository,
        _processor = processor,
        _health = health,
        _start = DateTime.now().subtract(const Duration(days: 30)),
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Permissions — только если есть реальный Health (не тест с моком).
      if (_health != null) {
        final granted = await checkAndRequestPermissions(_health);
        if (!granted) {
          _error = 'Нет разрешений для доступа к Health Connect';
          return;
        }
      }

      // Загружаем сырые точки веса батчем за весь диапазон.
      final weightPoints = await _repo.fetchRawData(
        types: const [HealthDataType.WEIGHT],
        startDate: _start,
        endDate: _end,
      );

      // Загружаем сырые точки шагов + агрегированные значения по каждой дате.
      final stepsPoints = await _repo.fetchRawData(
        types: const [HealthDataType.STEPS],
        startDate: _start,
        endDate: _end,
      );

      // Агрегация шагов по каждой дате в диапазоне (нативный aggregate()).
      final aggregatedByDate = <DateKey, int>{};
      for (var d = 0; d <= _end.difference(_start).inDays; d++) {
        final date = DateKey(_start.add(Duration(days: d)));
        final agg = await _repo.aggregateExternalSteps(date);
        if (agg != null && agg > 0) aggregatedByDate[date] = agg;
      }

      // Резолюция приоритета источников (Tier 1 → Tier 2).
      final weightResolved = _processor.resolveWeightForAllDates(weightPoints);
      final stepsResolved = _processor.resolveStepsForAllDates(stepsPoints, aggregatedByDate);

      // Обновляем кеши.
      _weightCache
        ..clear()
        ..addAll(weightResolved);
      _stepsCache
        ..clear()
        ..addAll(stepsResolved);

      // EMA пересчитывается по актуальному кешу весов.
      _emaCache = _processor.computeEma(_weightCache, _emaPeriod);

      _refreshChartData();
    } catch (e) {
      _error = 'Ошибка загрузки: $e';
      debugPrint('DashboardViewModel.load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Перезагружает данные для одной даты после submit/cancel.
  ///
  /// Не очищает весь кеш — только обновляет значение для конкретной даты,
  /// затем пересчитывает EMA (для веса — по всему кешу, т.к. EMA скользящее).
  Future<void> _reloadDate(DateKey date, MetricType type) async {
    if (type == MetricType.weight) {
      final weightPoints = await _repo.fetchRawData(
        types: const [HealthDataType.WEIGHT],
        startDate: date.startOfDay,
        endDate: date.endOfDay,
      );
      final resolved = _processor.resolveWeightForDate(date, weightPoints);
      if (resolved != null) {
        _weightCache[date] = resolved;
      } else {
        _weightCache.remove(date);
      }
      // EMA пересчитывается по всему кешу весов — правка даты влияет на все даты после.
      _emaCache = _processor.computeEma(_weightCache, _emaPeriod);
    } else {
      // Шаги — не накопительны, пересчёт EMA не нужен.
      final stepsPoints = await _repo.fetchRawData(
        types: const [HealthDataType.STEPS],
        startDate: date.startOfDay,
        endDate: date.endOfDay,
      );
      final agg = await _repo.aggregateExternalSteps(date);
      final resolved = _processor.resolveStepsForDate(date, stepsPoints, agg);
      if (resolved != null) {
        _stepsCache[date] = resolved;
      } else {
        _stepsCache.remove(date);
      }
    }
    _refreshChartData();
    notifyListeners();
  }

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

  // ─── API Фазы 3: подтверждение значения (секция 8 спеки) ─────────────────────

  /// Уже резолвленное значение + источник для конкретной даты.
  ///
  /// Новых обращений к Health Connect не требует — значение из in-memory кеша.
  /// Возвращает `null`, если данных нет (→ состояние `missing` в UI).
  ResolvedValue<num>? getResolvedValue(DateKey date, MetricType type) {
    switch (type) {
      case MetricType.weight:
        final w = _weightCache[date];
        if (w == null) return null;
        return ResolvedValue(value: w.weight, source: w.source);
      case MetricType.steps:
        final s = _stepsCache[date];
        if (s == null) return null;
        return ResolvedValue(value: s.steps, source: s.source);
    }
  }

  /// Пишет ручное значение (Tier 1) в Health Connect, обновляет кеш,
  /// при необходимости пересчитывает EMA, notifyListeners().
  Future<void> submitManualValue(DateKey date, MetricType type, num value) async {
    try {
      await _repo.writeManualRecord(date, type, value);
      await _reloadDate(date, type);
    } catch (e) {
      _error = 'Не удалось сохранить: $e';
      debugPrint('DashboardViewModel.submitManualValue error: $e');
      notifyListeners();
    }
  }

  /// Удаляет ручную запись (Tier 1), откатывает на Tier 2/missing,
  /// обновляет кеш, пересчитывает EMA при необходимости, notifyListeners().
  Future<void> cancelManualValue(DateKey date, MetricType type) async {
    try {
      await _repo.deleteManualRecord(date, type);
      await _reloadDate(date, type);
    } catch (e) {
      _error = 'Не удалось отменить: $e';
      debugPrint('DashboardViewModel.cancelManualValue error: $e');
      notifyListeners();
    }
  }
}