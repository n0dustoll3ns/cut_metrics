// Модель данных для дня питания
class NutritionDay {
  final DateTime date;
  final double calories; // ккал - приход энергии
  final double protein; // граммы
  final double fat; // граммы
  final double carbs; // граммы
  
  // Расход энергии за день (базальный метаболизм + активность)
  final double basalMetabolism; // базальный расход ккал
  final double activityCalories; // калории от активности (шаги, тренировки)
  
  NutritionDay({
    required this.date,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    this.basalMetabolism = 0,
    this.activityCalories = 0,
  });
  
  // Общая масса макронутриентов в граммах для расчета высоты столбца
  double get totalGrams => protein + fat + carbs;
  
  // Общий расход энергии
  double get totalEnergyExpenditure => basalMetabolism + activityCalories;
  
  // Энергобаланс (положительный = профицит, отрицательный = дефицит)
  double get energyBalance => calories - totalEnergyExpenditure;
}
