import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/expenditure_config.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Персистентные настройки — `shared_preferences` (Фаза 4 п.3: настройки
/// хранить можно, данные здоровья — нельзя).
///
/// Хранит:
/// - целевой темп, %/нед (слайдер 0.3–1.4);
/// - профиль расхода Фазы 7 (префикс `energy_`: пол, год рождения, рост,
///   режим BMR + ручной BMR, коэффициент шагов, параметры силовых, бытовой) —
///   A.2 спеки Фазы 7;
/// - дату последнего показанного саммари (пишется при показе; не гейтит
///   отображение — саммари пересчитывается при каждом открытии, U3);
/// - решения по источникам (Фаза 6, B): `src_decision.<metric>.<package>`
///   = `confirmed` | `refused`, отсутствие ключа = «спрашивать»;
/// - выбор источника на метрику (Фаза 6, C): `src_selection.<metric>`
///   = `auto` | `<package>`;
/// - режим темы (Фаза 6, D): `theme_mode` = `system` | `light` | `dark`
///   (строка, чтобы не тянуть Material-типы в сервис).
///
/// Миграция Фазы 7: ключ `activity_level` Фазы 5 перестаёт читаться —
/// игнорируется без ошибок (автомиграции нет, дефолты — A.2 спеки).
class SettingsService {
  static const _keyTargetPace = 'target_pace_percent';
  static const _keyLastSummaryShown = 'last_summary_shown_date';
  static const _keyThemeMode = 'theme_mode';

  // ─── Профиль расхода (Фаза 7, A.2) ──────────────────────────────────────────

  static const _keyEnergySex = 'energy_sex'; // m | f
  static const _keyEnergyBirthYear = 'energy_birth_year';
  static const _keyEnergyHeightCm = 'energy_height_cm'; // только ручной ввод
  static const _keyEnergyBmrMode = 'energy_bmr_mode'; // auto | manual
  static const _keyEnergyBmrManualKcal = 'energy_bmr_manual_kcal';
  static const _keyEnergyStepsKcalPerKgPerStep = 'energy_steps_kcal_per_kg_per_step';
  static const _keyEnergyTrainingFreq = 'energy_training_freq_per_week';
  static const _keyEnergyTrainingDurationMin = 'energy_training_duration_min';
  static const _keyEnergyTrainingIntensity = 'energy_training_intensity'; // moderate | heavy
  static const _keyEnergyTrainingKcalPerSession = 'energy_training_kcal_per_session';
  static const _keyEnergyHouseholdKcal = 'energy_household_kcal';

  static String _decisionKey(MetricType metric) => 'src_decision.${metric.name}';
  static String _selectionKey(MetricType metric) => 'src_selection.${metric.name}';

  /// Возвращает сохранённый целевой темп или дефолт [RecommendationConfig.defaultTargetPacePercent].
  Future<double> loadTargetPace() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyTargetPace) ?? RecommendationConfig.defaultTargetPacePercent;
  }

  Future<void> saveTargetPace(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTargetPace, value);
  }

  // ─── Профиль расхода (Фаза 7, A.2) ──────────────────────────────────────────

  /// Загружает профиль расхода: отсутствующие ключи — дефолты
  /// `ExpenditureProfile` (пол/год/рост/ручной BMR/своя сессия = `null`).
  ///
  /// [ExpenditureProfile.heightCm] здесь — ТОЛЬКО ручной ввод; HC-префилл
  /// подставляет VM поверх него.
  Future<ExpenditureProfile> loadEnergyProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return ExpenditureProfile(
      sex: switch (prefs.getString(_keyEnergySex)) {
        'm' => EnergySex.male,
        'f' => EnergySex.female,
        _ => null,
      },
      birthYear: prefs.getInt(_keyEnergyBirthYear),
      heightCm: prefs.getDouble(_keyEnergyHeightCm),
      bmrMode: prefs.getString(_keyEnergyBmrMode) == 'manual' ? BmrMode.manual : BmrMode.auto,
      bmrManualKcal: prefs.getDouble(_keyEnergyBmrManualKcal),
      stepsKcalPerKgPerStep:
          prefs.getDouble(_keyEnergyStepsKcalPerKgPerStep) ??
          ExpenditureConfig.defaultStepsKcalPerKgPerStep,
      trainingFreqPerWeek: (prefs.getInt(_keyEnergyTrainingFreq) ?? 0).clamp(0, 7),
      trainingDurationMin: prefs.getInt(_keyEnergyTrainingDurationMin) ?? 60,
      trainingIntensity:
          prefs.getString(_keyEnergyTrainingIntensity) == 'heavy'
              ? TrainingIntensity.heavy
              : TrainingIntensity.moderate,
      trainingKcalPerSession: prefs.getDouble(_keyEnergyTrainingKcalPerSession),
      householdKcal:
          prefs.getDouble(_keyEnergyHouseholdKcal) ?? ExpenditureConfig.defaultHouseholdKcal,
    );
  }

  /// Сохраняет профиль расхода целиком (применение мгновенное, без «Сохранить»).
  Future<void> saveEnergyProfile(ExpenditureProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEnergySex, switch (profile.sex) {
      EnergySex.male => 'm',
      EnergySex.female => 'f',
      null => '',
    });
    if (profile.birthYear != null) {
      await prefs.setInt(_keyEnergyBirthYear, profile.birthYear!);
    } else {
      await prefs.remove(_keyEnergyBirthYear);
    }
    if (profile.heightCm != null) {
      await prefs.setDouble(_keyEnergyHeightCm, profile.heightCm!);
    } else {
      await prefs.remove(_keyEnergyHeightCm);
    }
    await prefs.setString(
      _keyEnergyBmrMode,
      profile.bmrMode == BmrMode.manual ? 'manual' : 'auto',
    );
    if (profile.bmrManualKcal != null) {
      await prefs.setDouble(_keyEnergyBmrManualKcal, profile.bmrManualKcal!);
    } else {
      await prefs.remove(_keyEnergyBmrManualKcal);
    }
    await prefs.setDouble(_keyEnergyStepsKcalPerKgPerStep, profile.stepsKcalPerKgPerStep);
    await prefs.setInt(_keyEnergyTrainingFreq, profile.trainingFreqPerWeek.clamp(0, 7));
    await prefs.setInt(_keyEnergyTrainingDurationMin, profile.trainingDurationMin);
    await prefs.setString(
      _keyEnergyTrainingIntensity,
      profile.trainingIntensity == TrainingIntensity.heavy ? 'heavy' : 'moderate',
    );
    if (profile.trainingKcalPerSession != null) {
      await prefs.setDouble(_keyEnergyTrainingKcalPerSession, profile.trainingKcalPerSession!);
    } else {
      await prefs.remove(_keyEnergyTrainingKcalPerSession);
    }
    await prefs.setDouble(_keyEnergyHouseholdKcal, profile.householdKcal);
  }

  /// Дата последнего показанного саммари (null — ещё не показывали).
  Future<DateTime?> loadLastSummaryShownDate() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_keyLastSummaryShown);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> saveLastSummaryShownDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSummaryShown, date.millisecondsSinceEpoch);
  }

  // ─── Решения по источникам (Фаза 6, B) ──────────────────────────────────────

  /// Все решения по источникам для метрики: пакет → решение.
  ///
  /// В хранилище лежат только `confirmed`/`refused` — отсутствие ключа
  /// означает [ConfirmDecision.none] («спрашивать»).
  Future<Map<String, ConfirmDecision>> loadSourceDecisions(MetricType metric) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, ConfirmDecision>{};
    final prefix = '${_decisionKey(metric)}.';
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final package = key.substring(prefix.length);
      if (package.isEmpty) continue;
      result[package] = switch (prefs.getString(key)) {
        'confirmed' => ConfirmDecision.confirmed,
        'refused' => ConfirmDecision.refused,
        _ => ConfirmDecision.none,
      };
    }
    return result;
  }

  /// Сохраняет решение для пары (метрика, источник). [ConfirmDecision.none]
  /// удаляет ключ («сбросить решение»).
  Future<void> saveSourceDecision(
    MetricType metric,
    String package,
    ConfirmDecision decision,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_decisionKey(metric)}.$package';
    if (decision == ConfirmDecision.none) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, decision.name);
    }
  }

  // ─── Выбор источника на метрику (Фаза 6, C) ─────────────────────────────────

  /// Выбранный источник для метрики. Дефолт — «Авто».
  Future<SourceSelection> loadSourceSelection(MetricType metric) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_selectionKey(metric));
    if (value == null || value.isEmpty || value == 'auto') {
      return const SourceSelection.auto();
    }
    return SourceSelection.app(value);
  }

  Future<void> saveSourceSelection(MetricType metric, SourceSelection selection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectionKey(metric), selection.package ?? 'auto');
  }

  // ─── Режим темы (Фаза 6, D) ─────────────────────────────────────────────────

  /// Имя режима темы: `system` | `light` | `dark`. Дефолт — `system`.
  Future<String> loadThemeModeName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeMode) ?? 'system';
  }

  Future<void> saveThemeModeName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, name);
  }
}
