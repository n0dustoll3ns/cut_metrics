/// Типы метрик, для которых можно настраивать приоритеты источников.
enum MetricType {
  weight,
  steps,
  sleep,
  nutrition;

  /// Человекочитаемое название метрики.
  String get label => switch (this) {
    MetricType.weight => 'Вес',
    MetricType.steps => 'Шаги',
    MetricType.sleep => 'Сон',
    MetricType.nutrition => 'Питание',
  };
}