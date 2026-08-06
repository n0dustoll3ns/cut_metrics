import 'dart:convert';

import 'package:cut_metrics/old_proj/domain/metric_type.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для загрузки/сохранения приоритетов источников данных.
///
/// Приоритеты хранятся как JSON в [SharedPreferences]:
/// ключ — имя метрики, значение — упорядоченный список sourceId.
/// Индекс 0 = наивысший приоритет.
class SourcePrioritiesService {
  static const _keyPrefix = 'source_priorities_';

  /// Загружает приоритеты для конкретной метрики.
  /// Возвращает пустой список, если настройки отсутствуют.
  Future<List<String>> load(MetricType metric) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_keyPrefix${metric.name}');
      if (json == null || json.isEmpty) return [];
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      debugPrint('SourcePrioritiesService.load($metric) error: $e');
      return [];
    }
  }

  /// Загружает приоритеты для всех метрик сразу.
  Future<Map<MetricType, List<String>>> loadAll() async {
    final result = <MetricType, List<String>>{};
    for (final metric in MetricType.values) {
      result[metric] = await load(metric);
    }
    return result;
  }

  /// Сохраняет приоритеты для конкретной метрики.
  Future<void> save(MetricType metric, List<String> sourceIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(sourceIds);
      await prefs.setString('$_keyPrefix${metric.name}', json);
    } catch (e) {
      debugPrint('SourcePrioritiesService.save($metric) error: $e');
    }
  }
}