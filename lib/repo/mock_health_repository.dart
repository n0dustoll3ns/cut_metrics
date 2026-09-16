import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/repo/health_repository.dart';
import 'package:health/health.dart';

/// Идентификатор пакета приложения — определяет Tier 1 записи.
const kAppPackageId = 'com.example.cut_metrics';

/// Внешний источник по умолчанию для мока (Google Fit).
const kExternalSourceId = 'com.google.android.apps.fitness';

/// Источник питания в моке Фазы 7 (MyFitnessPal).
const kNutritionSourceId = 'com.myfitnesspal.android';

/// Источник HC BASAL в моке Фазы 7 (Samsung Health).
const kBasalSourceId = 'com.sec.android.app.shealth';

/// Mock-реализация [HealthRepository] для юнит-тестов.
///
/// В отличие от реального репозитория, хранит данные в памяти и позволяет
/// тестам напрямую управлять содержимым через методы `add*`.
///
/// Ключевое: генерирует записи с разным пакетом источника (пакет приложения /
/// внешние приложения) и разным `recordingMethod` (manual / automatic), что
/// необходимо для тестирования резолюции приоритета источников.
///
/// Фаза 6: точки создаются как на реальном Android (A0-лог) — `sourceId`
/// пустой, пакет приложения приходит в `sourceName` (= `dataOrigin.packageName`).
/// Это заставляет тесты гонять реальный путь определения источника
/// (`HealthDataProcessor.sourcePackageOf`).
class MockHealthRepository implements HealthRepository {
  /// Идентификатор пакета приложения — определяет Tier 1.
  final String appPackageId;

  /// Счётчик вызовов `fetchRawData` (для тестов Фазы 4, DoD 3).
  int fetchRawDataCallCount = 0;

  /// Внутреннее хранилище всех точек данных.
  final List<HealthDataPoint> _points = [];

  /// Доступ только для чтения к внутреннему хранилищу (для тестов).
  List<HealthDataPoint> get points => List.unmodifiable(_points);

  MockHealthRepository({this.appPackageId = kAppPackageId});

  // ─── Управление данными для тестов ──────────────────────────────────────────

  /// Добавляет точку напрямую (низкоуровневый API для тестов).
  void addPoint(HealthDataPoint point) => _points.add(point);

  /// Добавляет внешнюю запись веса (Tier 2).
  void addExternalWeight(DateTime date, double weight, {String? sourcePackage}) {
    addPoint(
      _makeWeightPoint(date, weight, sourcePackage ?? kExternalSourceId, RecordingMethod.automatic),
    );
  }

  /// Добавляет ручную запись веса (Tier 1).
  void addManualWeight(DateTime date, double weight) {
    addPoint(_makeWeightPoint(date, weight, appPackageId, RecordingMethod.manual));
  }

  /// Добавляет внешнюю запись шагов (Tier 2).
  void addExternalSteps(DateTime date, int steps, {String? sourcePackage}) {
    addPoint(
      _makeStepsPoint(date, steps, sourcePackage ?? kExternalSourceId, RecordingMethod.automatic),
    );
  }

  /// Добавляет ручную запись шагов (Tier 1).
  void addManualSteps(DateTime date, int steps) {
    addPoint(_makeStepsPoint(date, steps, appPackageId, RecordingMethod.manual));
  }

  /// Добавляет интервал стадии сна (DEEP/LIGHT/REM) — внешний трекер.
  ///
  /// [from]/[to] — точные временные метки (не день): интервалы сна пересекают
  /// полночь, анализатор группирует их по правилу «после 12:00 → следующий день».
  void addSleepStage(
    DateTime from,
    DateTime to, {
    HealthDataType type = HealthDataType.SLEEP_LIGHT,
    String sourcePackage = kExternalSourceId,
  }) {
    assert(
      type == HealthDataType.SLEEP_DEEP ||
          type == HealthDataType.SLEEP_LIGHT ||
          type == HealthDataType.SLEEP_REM,
      'addSleepStage expects a sleep stage type, got $type',
    );
    addPoint(_makeIntervalPoint(from, to, type, sourcePackage));
  }

  /// Добавляет интервал общей длительности сна (`SLEEP_ASLEEP`) — внешний трекер.
  void addSleepAsleep(
    DateTime from,
    DateTime to, {
    String sourcePackage = kExternalSourceId,
  }) {
    addPoint(_makeIntervalPoint(from, to, HealthDataType.SLEEP_ASLEEP, sourcePackage));
  }

  // ─── Управление данными Фазы 7 (питание / BASAL / рост) ─────────────────────

  /// Добавляет внешний приём пищи (Tier 2, NUTRITION). Несколько вызовов за
  /// один день = несколько приёмов (трекеры пишут по пункту/приёму пищи).
  void addExternalNutrition(
    DateTime date, {
    required double calories,
    double? protein,
    double? fat,
    double? carbs,
    String sourcePackage = kNutritionSourceId,
    String name = 'Приём пищи',
  }) {
    addPoint(
      _makeNutritionPoint(
        date,
        calories,
        protein,
        fat,
        carbs,
        sourcePackage,
        RecordingMethod.automatic,
        name: name,
      ),
    );
  }

  /// Добавляет наш «Итог дня» (Tier 1, NUTRITION) — одна запись на день.
  void addManualNutrition(
    DateTime date, {
    required double calories,
    double? protein,
    double? fat,
    double? carbs,
  }) {
    addPoint(
      _makeNutritionPoint(
        date,
        calories,
        protein,
        fat,
        carbs,
        appPackageId,
        RecordingMethod.manual,
        name: 'Итог дня',
      ),
    );
  }

  /// Добавляет внешнюю запись HC BASAL (ккал/день) — Samsung Health и т.п.
  void addBasal(DateTime date, double kcalPerDay, {String? sourcePackage}) {
    addPoint(
      _makePoint(
        date,
        HealthDataType.BASAL_ENERGY_BURNED,
        kcalPerDay,
        sourcePackage ?? kBasalSourceId,
        recordingMethod: RecordingMethod.automatic,
      ),
    );
  }

  /// Добавляет внешнюю запись роста (см).
  void addHeight(DateTime date, double cm, {String? sourcePackage}) {
    addPoint(
      _makePoint(
        date,
        HealthDataType.HEIGHT,
        cm,
        sourcePackage ?? kExternalSourceId,
        recordingMethod: RecordingMethod.automatic,
      ),
    );
  }

  /// Детерминированный seed данных Фазы 7 (A.9): NUTRITION — 3–6 приёмов/день
  /// с ккал и БЖУ от «MyFitnessPal», 2 дня без записей; BASAL — 1 точка/день
  /// ~1650–1690 ккал от «Samsung Health»; HEIGHT — 178 см. Без `Random` —
  /// одни и те же данные на одних и тех же входах (тест «детерминированность»).
  ///
  /// [end] — последний день диапазона (обычно «сегодня»), [days] — длина.
  void seedPhase7Data({required DateTime end, int days = 30}) {
    for (var i = days - 1; i >= 0; i--) {
      final date = end.subtract(Duration(days: i));

      // BASAL — каждый день (1 точка/день, A.9), даже в дни без питания.
      addBasal(date, 1650 + (i % 5) * 10);

      // Два дня без данных питания (не «0 ккал», а именно отсутствие записей).
      if (i == 13 || i == 20) continue;

      final mealCount = 3 + (i % 4); // 3–6 приёмов
      for (var m = 0; m < mealCount; m++) {
        final kcal = 350.0 + ((i * 7 + m * 113) % 18) * 25.0; // 350–775
        addExternalNutrition(
          date,
          calories: kcal,
          protein: (kcal * 0.30 / 4).roundToDouble(),
          fat: (kcal * 0.25 / 9).roundToDouble(),
          carbs: (kcal * 0.45 / 4).roundToDouble(),
          name: 'Блюдо ${m + 1}',
        );
      }
    }

    addHeight(end.subtract(const Duration(days: 200)), 178);
  }

  /// Очищает все данные (для изоляции тестов).
  void clear() {
    _points.clear();
  }

  // ─── Реализация HealthRepository ────────────────────────────────────────────

  /// Наша ли точка (Tier 1) — по пакету источника, как на Android (A0).
  bool _isOurPoint(HealthDataPoint p) =>
      HealthDataProcessor.sourcePackageOf(p) == appPackageId;

  @override
  Future<bool> hasManualRecord(DateKey date, MetricType type) async {
    final healthType = _toHealthDataType(type);
    return _points.any(
      (p) => _isOurPoint(p) && p.type == healthType && DateKey(p.dateFrom) == date,
    );
  }

  @override
  Future<void> writeManualRecord(DateKey date, MetricType type, num value) async {
    final healthType = _toHealthDataType(type);
    // Delete-then-write (идемпотентность, A1.1) — как в реальном репозитории.
    _points.removeWhere(
      (p) => _isOurPoint(p) && p.type == healthType && DateKey(p.dateFrom) == date,
    );
    final point = _makePoint(date.value, healthType, value, appPackageId);
    _points.add(point);
  }

  @override
  Future<void> deleteManualRecord(DateKey date, MetricType type) async {
    final healthType = _toHealthDataType(type);
    _points.removeWhere(
      (p) => _isOurPoint(p) && p.type == healthType && DateKey(p.dateFrom) == date,
    );
  }

  // ─── Реализация HealthRepository: «Итог дня» (Фаза 7, A.7) ──────────────────

  @override
  Future<bool> hasManualNutrition(DateKey date) async {
    return _points.any(
      (p) =>
          _isOurPoint(p) && p.type == HealthDataType.NUTRITION && DateKey(p.dateFrom) == date,
    );
  }

  @override
  Future<void> writeManualNutrition(
    DateKey date, {
    required double calories,
    double? protein,
    double? fat,
    double? carbs,
  }) async {
    // Delete-then-write — как в реальном репозитории (идемпотентность).
    _points.removeWhere(
      (p) =>
          _isOurPoint(p) && p.type == HealthDataType.NUTRITION && DateKey(p.dateFrom) == date,
    );
    _points.add(
      _makeNutritionPoint(
        date.value,
        calories,
        protein,
        fat,
        carbs,
        appPackageId,
        RecordingMethod.manual,
        name: 'Итог дня',
      ),
    );
  }

  @override
  Future<void> deleteManualNutrition(DateKey date) async {
    _points.removeWhere(
      (p) =>
          _isOurPoint(p) && p.type == HealthDataType.NUTRITION && DateKey(p.dateFrom) == date,
    );
  }

  @override
  Future<List<HealthDataPoint>> fetchRawData({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    fetchRawDataCallCount++;
    return _points.where((p) {
      if (!types.contains(p.type)) return false;
      final dayStart = DateTime(p.dateFrom.year, p.dateFrom.month, p.dateFrom.day);
      final s = DateTime(startDate.year, startDate.month, startDate.day);
      final e = DateTime(endDate.year, endDate.month, endDate.day);
      return !dayStart.isBefore(s) && !dayStart.isAfter(e);
    }).toList();
  }

  // ─── Вспомогательные методы ─────────────────────────────────────────────────

  HealthDataType _toHealthDataType(MetricType type) => switch (type) {
    MetricType.weight => HealthDataType.WEIGHT,
    MetricType.steps => HealthDataType.STEPS,
    // Питание ходит через writeManualNutrition (отдельный контракт) —
    // кейс для полноты switch.
    MetricType.nutrition => HealthDataType.NUTRITION,
  };

  HealthDataPoint _makePoint(
    DateTime date,
    HealthDataType type,
    num value,
    String sourcePackage, {
    RecordingMethod recordingMethod = RecordingMethod.manual,
  }) {
    return switch (type) {
      HealthDataType.WEIGHT =>
        _makeWeightPoint(date, value.toDouble(), sourcePackage, recordingMethod),
      HealthDataType.STEPS => _makeStepsPoint(date, value.toInt(), sourcePackage, recordingMethod),
      // Числовые instant-записи Фазы 7: BASAL (ккал/день) и HEIGHT (см) —
      // NumericHealthValue, как отдаёт HC.
      HealthDataType.BASAL_ENERGY_BURNED ||
      HealthDataType.HEIGHT =>
        _makeNumericInstantPoint(date, type, value.toDouble(), sourcePackage, recordingMethod),
      _ => throw ArgumentError('Unsupported type for mock: $type'),
    };
  }

  /// Числовая instant-запись (BASAL/HEIGHT): `dateFrom == dateTo` — HC пишет
  /// их моментальными (`record.time`), интервалов нет.
  HealthDataPoint _makeNumericInstantPoint(
    DateTime date,
    HealthDataType type,
    double value,
    String sourcePackage,
    RecordingMethod recordingMethod,
  ) {
    final at = DateTime(date.year, date.month, date.day, 12);
    return HealthDataPoint(
      sourceName: sourcePackage,
      uuid: '',
      sourceDeviceId: '',
      sourceId: '',
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      value: NumericHealthValue(numericValue: value),
      dateFrom: at,
      dateTo: at,
      type: type,
      unit: type == HealthDataType.HEIGHT ? HealthDataUnit.METER : HealthDataUnit.KILOCALORIE,
      recordingMethod: recordingMethod,
    );
  }

  /// Точка питания (NUTRITION) — `NutritionHealthValue`, как на Android.
  HealthDataPoint _makeNutritionPoint(
    DateTime date,
    double? calories,
    double? protein,
    double? fat,
    double? carbs,
    String sourcePackage,
    RecordingMethod recordingMethod, {
    required String name,
  }) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));
    return HealthDataPoint(
      sourceName: sourcePackage,
      uuid: '',
      sourceDeviceId: '',
      sourceId: '',
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      value: NutritionHealthValue(
        name: name,
        mealType: 'UNKNOWN',
        calories: calories,
        protein: protein,
        fat: fat,
        carbs: carbs,
      ),
      dateFrom: dayStart,
      dateTo: dayEnd,
      type: HealthDataType.NUTRITION,
      unit: HealthDataUnit.KILOCALORIE,
      recordingMethod: recordingMethod,
    );
  }

  /// Точка «как на реальном Android» (A0-лог): `sourceId` пустой, пакет
  /// приложения-источника приходит в `sourceName`.
  HealthDataPoint _makeWeightPoint(
    DateTime date,
    double weight,
    String sourcePackage,
    RecordingMethod recordingMethod,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));
    return HealthDataPoint(
      sourceName: sourcePackage,
      uuid: '',
      sourceDeviceId: '',
      sourceId: '',
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      value: NumericHealthValue(numericValue: weight),
      dateFrom: dayStart,
      dateTo: dayEnd,
      type: HealthDataType.WEIGHT,
      unit: HealthDataUnit.KILOGRAM,
      recordingMethod: recordingMethod,
    );
  }

  HealthDataPoint _makeIntervalPoint(
    DateTime from,
    DateTime to,
    HealthDataType type,
    String sourcePackage,
  ) {
    return HealthDataPoint(
      sourceName: sourcePackage,
      uuid: '',
      sourceDeviceId: '',
      sourceId: '',
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      value: NumericHealthValue(numericValue: to.difference(from).inMinutes),
      dateFrom: from,
      dateTo: to,
      type: type,
      unit: HealthDataUnit.MINUTE,
      recordingMethod: RecordingMethod.automatic,
    );
  }

  HealthDataPoint _makeStepsPoint(
    DateTime date,
    int steps,
    String sourcePackage,
    RecordingMethod recordingMethod,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));
    return HealthDataPoint(
      sourceName: sourcePackage,
      uuid: '',
      sourceDeviceId: '',
      sourceId: '',
      sourcePlatform: HealthPlatformType.googleHealthConnect,
      value: NumericHealthValue(numericValue: steps),
      dateFrom: dayStart,
      dateTo: dayEnd,
      type: HealthDataType.STEPS,
      unit: HealthDataUnit.COUNT,
      recordingMethod: recordingMethod,
    );
  }
}