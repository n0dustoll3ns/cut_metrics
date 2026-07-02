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

  // Накопленные сырые точки (для логирования)
  final List<HealthDataPoint> _rawLog = [];

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

        // Накапливаем сырые точки для логирования (с дедупликацией)
        _mergeRawLog(results.expand((list) => list));

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

  // ─── Логирование ────────────────────────────────────────────────────────────

  /// Добавляет сырые точки в лог с дедупликацией.
  /// Дедупликация: по uuid (если непустой), иначе по (type, dateFrom, dateTo, value).
  void _mergeRawLog(Iterable<HealthDataPoint> points) {
    final existing = <String>{};
    final existingKeys = <String>{};

    for (final p in _rawLog) {
      existing.add(p.uuid);
      existingKeys.add(_rawPointKey(p));
    }

    for (final p in points) {
      final uuid = p.uuid;
      final key = _rawPointKey(p);
      if (uuid.isNotEmpty && existing.contains(uuid)) continue;
      if (uuid.isEmpty && existingKeys.contains(key)) continue;
      _rawLog.add(p);
      existing.add(uuid);
      existingKeys.add(key);
    }
  }

  /// Ключ дедупликации для точки без uuid.
  String _rawPointKey(HealthDataPoint p) =>
      '${p.type}|${p.dateFrom.toIso8601String()}|${p.dateTo.toIso8601String()}|${p.value}';

  /// Форматирует DateTime как `yyyy-MM-dd`.
  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Форматирует DateTime как `yyyy-MM-dd HH:mm`.
  String _fmtDateTime(DateTime d) =>
      '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Разделитель таблицы.
  String _divider(int width) => '─' * width;

  /// Строит текстовый лог в табличном формате для каждого типа данных.
  /// Возвращает Map: имя файла -> содержимое.
  Map<String, String> buildLogs() {
    return {
      'raw_weight.txt': _buildRawWeightLog(),
      'raw_steps.txt': _buildRawStepsLog(),
      'raw_sleep.txt': _buildRawSleepLog(),
      'raw_nutrition.txt': _buildRawNutritionLog(),
      'weight.txt': _buildWeightLog(),
      'ema.txt': _buildEmaLog(),
      'sleep.txt': _buildSleepLog(),
      'steps.txt': _buildStepsLog(),
      'nutrition.txt': _buildNutritionLog(),
    };
  }

  String _buildRawWeightLog() {
    final points = _rawLog.where((p) => p.type == HealthDataType.WEIGHT).toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final header = '📅 Date & Time         ⚖️ Weight (kg)  Source';
    final sep = _divider(60);
    final rows = points.map((p) {
      final w = (p.value as NumericHealthValue).numericValue.toDouble();
      return '   ${_fmtDateTime(p.dateFrom).padRight(19)}  ${w.toStringAsFixed(1).padLeft(12)}  ${p.sourceId}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }

  String _buildRawStepsLog() {
    final points = _rawLog.where((p) => p.type == HealthDataType.STEPS).toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final header = '📅 Date & Time         👟 Steps       Source';
    final sep = _divider(55);
    final rows = points.map((p) {
      final s = (p.value as NumericHealthValue).numericValue.toInt();
      return '   ${_fmtDateTime(p.dateFrom).padRight(19)}  ${s.toString().padLeft(10)}  ${p.sourceId}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }

  String _buildRawSleepLog() {
    final points = _rawLog
        .where((p) => _sleepTypes.contains(p.type))
        .toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final header = '📅 Date & Time         😴 Type        Minutes  Source';
    final sep = _divider(65);
    final rows = points.map((p) {
      final m = (p.value as NumericHealthValue).numericValue.toDouble();
      final typeStr = p.type.name.replaceAll('SLEEP_', '');
      return '   ${_fmtDateTime(p.dateFrom).padRight(19)}  ${typeStr.padRight(11)}  ${m.toStringAsFixed(0).padLeft(7)}  ${p.sourceId}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }

  String _buildRawNutritionLog() {
    final points = _rawLog.where((p) => p.type == HealthDataType.NUTRITION).toList()
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final header = '📅 Date & Time         🍔 Cal    🥩 Prot(g)  🧈 Fat(g)  🍞 Carbs(g)  Source';
    final sep = _divider(85);
    final rows = points.map((p) {
      final v = p.value as NutritionHealthValue;
      final cal = v.calories?.toDouble() ?? 0;
      final prot = v.protein?.toDouble() ?? 0;
      final fat = v.fat?.toDouble() ?? 0;
      final carbs = v.carbs?.toDouble() ?? 0;
      return '   ${_fmtDateTime(p.dateFrom).padRight(19)}  '
          '${cal.toStringAsFixed(0).padLeft(7)}  '
          '${prot.toStringAsFixed(0).padLeft(10)}  '
          '${fat.toStringAsFixed(0).padLeft(8)}  '
          '${carbs.toStringAsFixed(0).padLeft(10)}  '
          '${p.sourceId}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }

  String _buildWeightLog() {
    final data = _weightCache.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final header = '📅 Date            ⚖️ Weight (kg)';
    final sep = _divider(35);
    final rows = data.map((d) {
      return '   ${_fmtDate(d.date.value).padRight(14)}  ${d.weight.toStringAsFixed(1).padLeft(12)}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }

  String _buildEmaLog() {
    final data = _emaCache.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final header = '📅 Date            📈 EMA (kg)';
    final sep = _divider(32);
    final rows = data.map((d) {
      return '   ${_fmtDate(d.date.value).padRight(14)}  ${d.weight.toStringAsFixed(1).padLeft(10)}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }

  String _buildSleepLog() {
    final data = _sleepCache.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final header = '📅 Date            😴 Deep(h)  Light(h)  REM(h)  Total(h)';
    final sep = _divider(55);
    final rows = data.map((d) {
      return '   ${_fmtDate(d.date.value).padRight(14)}  '
          '${d.deep.toStringAsFixed(1).padLeft(7)}  '
          '${d.light.toStringAsFixed(1).padLeft(8)}  '
          '${d.rem.toStringAsFixed(1).padLeft(6)}  '
          '${d.total.toStringAsFixed(1).padLeft(7)}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }

  String _buildStepsLog() {
    final data = _stepsCache.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final header = '📅 Date            👟 Steps';
    final sep = _divider(28);
    final rows = data.map((d) {
      return '   ${_fmtDate(d.date.value).padRight(14)}  ${d.steps.toString().padLeft(10)}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }

  String _buildNutritionLog() {
    final entries = _nutritionSessionsCache.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final header = '📅 Date            🍔 Cal    🥩 Prot(g)  🧈 Fat(g)  🍞 Carbs(g)';
    final sep = _divider(65);
    final rows = entries.map((e) {
      final day = _processor.aggregateNutritionDay(e.key, e.value);
      return '   ${_fmtDate(e.key.value).padRight(14)}  '
          '${day.calories.toStringAsFixed(0).padLeft(7)}  '
          '${day.protein.toStringAsFixed(0).padLeft(10)}  '
          '${day.fat.toStringAsFixed(0).padLeft(8)}  '
          '${day.carbs.toStringAsFixed(0).padLeft(10)}';
    }).join('\n');
    return '$header\n$sep\n${rows.isEmpty ? '(no data)' : rows}';
  }
}
