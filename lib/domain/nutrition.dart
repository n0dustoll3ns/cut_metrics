// Модель данных для дня питания
import 'package:cut_metrics/domain/date_extension.dart';

class NutritionDay {
  final DateKey date;
  final double calories; // ккал - приход энергии
  final double protein; // граммы
  final double fat; // граммы
  final double carbs; // граммы

  NutritionDay({
    required this.date,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  // Общая масса макронутриентов в граммах для расчета высоты столбца
  double get totalGrams => protein + fat + carbs;
}
