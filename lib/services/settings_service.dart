import 'package:cut_metrics/domain/activity_level.dart';
import 'package:cut_metrics/domain/confirm_decision.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/domain/source_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Персистентные настройки — `shared_preferences` (Фаза 4 п.3: настройки
/// хранить можно, данные здоровья — нельзя).
///
/// Хранит:
/// - целевой темп, %/нед (слайдер 0.3–1.4);
/// - уровень активности 1–5;
/// - дату последнего показанного саммари (пишется при показе; не гейтит
///   отображение — саммари пересчитывается при каждом открытии, U3);
/// - решения по источникам (Фаза 6, B): `src_decision.<metric>.<package>`
///   = `confirmed` | `refused`, отсутствие ключа = «спрашивать»;
/// - выбор источника на метрику (Фаза 6, C): `src_selection.<metric>`
///   = `auto` | `<package>`;
/// - режим темы (Фаза 6, D): `theme_mode` = `system` | `light` | `dark`
///   (строка, чтобы не тянуть Material-типы в сервис).
class SettingsService {
  static const _keyTargetPace = 'target_pace_percent';
  static const _keyActivityLevel = 'activity_level';
  static const _keyLastSummaryShown = 'last_summary_shown_date';
  static const _keyThemeMode = 'theme_mode';

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

  /// Возвращает сохранённый уровень активности или дефолт [ActivityLevel.level1].
  Future<ActivityLevel> loadActivityLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return ActivityLevel.byNumber(prefs.getInt(_keyActivityLevel) ?? 1);
  }

  Future<void> saveActivityLevel(ActivityLevel level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyActivityLevel, level.number);
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
