import 'package:collection/collection.dart';
import 'package:cut_metrics/domain/date_extension.dart';
import 'package:cut_metrics/domain/processer.dart';
import 'package:cut_metrics/domain/weight.dart';
import 'package:cut_metrics/domain/nutrition.dart';
import 'package:cut_metrics/domain.dart';
import 'package:cut_metrics/repo/health.dart';
import 'package:flutter/material.dart';
import 'package:health/health.dart';

/// ViewModel дашборда.
/// Отвечает только за состояние UI и оркестрацию слоёв ниже.
class ViewModel extends ChangeNotifier {
  final HealthRepository repo;
  final HealthDataProcessor _processor;

  static const _sleepTypes = [
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
  ];
  static const _weightTypes = [HealthDataType.WEIGHT];
  static const _nutritionTypes = [HealthDataType.NUTRITION];
  static const _stepsTypes = [HealthDataType.STEPS];
  static const _allTypes = [..._sleepTypes, ..._weightTypes, ..._nutritionTypes, ..._stepsTypes];

  // ─── Публичное состояние ────────────────────────────────────────────────────

  DateTime get start => _start;
  DateTime get end => _end;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<WeightDay> get weightData => _weightData;
  List<WeightDay> get emaData => _emaData;
  List<NutritionDay> get nutritionData => _nutritionData;
  List<SleepDay> get sleepData => _sleepData;
  List<StepsDay> get stepsData => _stepsData;

  // ─── Приватное состояние ────────────────────────────────────────────────────

  DateTime _start = DateTime.now().subtract(const Duration(days: 7));
  DateTime _end = DateTime.now();
  bool _isLoading = false;
  String? _error;

  // Кеши обработанных данных (всё загруженное, не только видимый диапазон)
  final Map<DateKey, WeightDay> _weightCache = {};
  Map<DateKey, WeightDay> _emaCache = {};
  final Map<DateKey, SleepDay> _sleepCache = {};
  final Map<DateKey, StepsDay> _stepsCache = {};
  // Кеш питания теперь хранит дедуплицированные кластеры (приёмы пищи)
  final Map<DateKey, List<MealSession>> _nutritionSessionsCache = {};

  // Данные для текущего выбранного диапазона (идут в UI)
  List<WeightDay> _weightData = [];
  List<WeightDay> _emaData = [];
  List<NutritionDay> _nutritionData = [];
  List<SleepDay> _sleepData = [];
  List<StepsDay> _stepsData = [];

  // Загруженный диапазон (чтобы не перезапрашивать то, что уже есть)
  DateTimeRange? _loadedRange;

  // Если пока шла загрузка был запущен новый _load(), устаревший результат отбрасывается.
  int _loadGeneration = 0;

  ViewModel({required HealthRepository repository, HealthDataProcessor? processor})
    : repo = repository,
      _processor = processor ?? HealthDataProcessor() {
    _load();
  }

  // ─── Публичный API ──────────────────────────────────────────────────────────

  /// Устанавливает новый диапазон дат.
  /// Если [start] >= [end], вторая дата сдвигается на неделю вперёд/назад.
  Future<void> setDate({DateTime? start, DateTime? end}) async {
    if (start != null) _start = start;
    if (end != null) _end = end;

    // Гарантируем, что start < end
    if (!_start.isBefore(_end)) {
      if (start != null) {
        // Пользователь менял начало — двигаем конец вперёд
        _end = _start.add(const Duration(days: 7));
      } else {
        // Пользователь менял конец — двигаем начало назад
        _start = _end.subtract(const Duration(days: 7));
      }
    }

    await _load();
  }

  // ─── Приватные методы ───────────────────────────────────────────────────────

  /// Определяет, какой участок ещё не загружен.
  DateTimeRange? get _unloadedRange {
    if (_loadedRange == null) return DateTimeRange(start: _start, end: _end);
    return DateTimeRange(start: _start, end: _end).getUncoveredRange(_loadedRange!);
  }

  /// Период EMA зависит от длины выбранного диапазона.
  int get _emaPeriod {
    final days = _end.difference(_start).inDays;
    if (days >= 20) return 10;
    if (days >= 10) return 5;
    return 3;
  }

  Future<void> _load() async {
    // Любой более новый вызов _load() увеличит счётчик, и мы поймём, что устарели.
    final generation = ++_loadGeneration;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final interval = _unloadedRange;

      if (interval != null) {
        final granted = await repo.checkAndRequestPermissions(_allTypes);

        // Проверяем актуальность после await
        if (generation != _loadGeneration) return;

        if (!granted) {
          _error = 'Permission denied or SDK unavailable';
          return;
        }

        // Параллельная загрузка всех четырёх типов.
        final results = await Future.wait([
          repo.fetchRawData(types: _weightTypes, startDate: interval.start, endDate: interval.end),
          repo.fetchRawData(types: _stepsTypes, startDate: interval.start, endDate: interval.end),
          repo.fetchRawData(types: _sleepTypes, startDate: interval.start, endDate: interval.end),
          repo.fetchRawData(types: _nutritionTypes, startDate: interval.start, endDate: interval.end),
        ]);

        // Проверяем актуальность после await (запросы могли занять время)
        if (generation != _loadGeneration) return;

        _processor.mergeWeightInto(_weightCache, results[0]);
        _processor.mergeStepsInto(_stepsCache, results[1]);
        _processor.mergeSleepInto(_sleepCache, results[2], interval.start, interval.end);
        _processor.mergeNutritionInto(_nutritionSessionsCache, results[3]);

        // Расширяем известный загруженный диапазон
        _loadedRange = _mergeRanges(_loadedRange, interval);
      }

      // EMA всегда пересчитывается по актуальному кешу
      _emaCache = _processor.computeEma(_weightCache, _emaPeriod);

      _refreshChartData();
    } catch (e) {
      if (generation != _loadGeneration) return;
      _error = 'Failed to load: $e';
      debugPrint('ViewModel error: $e');
    } finally {
      // Обновляем UI только если это актуальное поколение запроса
      if (generation == _loadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Фильтрует кеши по текущему диапазону дат для UI.
  void _refreshChartData() {
    bool inRange(DateKey k) => k.value.isInsideInterval(_start, _end);
    List<T> fromCache<T extends Object>(Map<DateKey, T> cache, Comparator<T> cmp) =>
        cache.entries.where((e) => inRange(e.key)).map((e) => e.value).sorted(cmp);

    _weightData = fromCache(_weightCache, (a, b) => a.date.compareTo(b.date));
    _emaData = fromCache(_emaCache, (a, b) => a.date.compareTo(b.date));

    // Агрегируем сессии питания в NutritionDay на лету
    final nutritionDays = <NutritionDay>[];
    for (final entry in _nutritionSessionsCache.entries) {
      if (inRange(entry.key)) {
        nutritionDays.add(_processor.aggregateNutritionDay(entry.key, entry.value));
      }
    }
    nutritionDays.sort((a, b) => a.date.compareTo(b.date));
    _nutritionData = nutritionDays;

    _sleepData = fromCache(_sleepCache, (a, b) => a.date.compareTo(b.date));
    _stepsData = fromCache(_stepsCache, (a, b) => a.date.compareTo(b.date));
  }

  /// Объединяет два диапазона в один охватывающий оба.
  DateTimeRange _mergeRanges(DateTimeRange? existing, DateTimeRange next) {
    if (existing == null) return next;
    return DateTimeRange(
      start: existing.start.isBefore(next.start) ? existing.start : next.start,
      end: existing.end.isAfter(next.end) ? existing.end : next.end,
    );
  }
}
