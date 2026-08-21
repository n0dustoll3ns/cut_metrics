import 'package:cut_metrics/domain/activity_level.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Персистентные настройки Фазы 5 — `shared_preferences` (Фаза 4 п.3: настройки
/// хранить можно, данные здоровья — нельзя).
///
/// Хранит:
/// - целевой темп, %/нед (слайдер 0.3–1.4);
/// - уровень активности 1–5;
/// - дату последнего показанного саммари (пишется при показе; не гейтит
///   отображение — саммари пересчитывается при каждом открытии, U3).
class SettingsService {
  static const _keyTargetPace = 'target_pace_percent';
  static const _keyActivityLevel = 'activity_level';
  static const _keyLastSummaryShown = 'last_summary_shown_date';

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
}
