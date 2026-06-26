// Модель данных для дня с весом
import 'package:cut_metrics/domain/date_extension.dart';

class WeightDay {
  final DateKey date;
  final double weight; // вес в кг

  WeightDay({
    required this.date,
    required this.weight,
  });
}
