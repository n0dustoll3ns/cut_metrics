import 'dart:math';

import 'package:cut_metrics/domain.dart';
import 'package:cut_metrics/view_model.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

/// Стековый столбчатый график макронутриентов (белки / жиры / углеводы).
/// Каждый столбец состоит из трёх сегментов, наложенных друг на друга.
class NutritionChart extends StatelessWidget {
  const NutritionChart({super.key});

  // Цвета сегментов — совпадают с легендой.
  static const _proteinColor = Color(0xFF4A5DCB);
  static const _fatColor = Color(0xFFF9C620);
  static const _carbsColor = Color(0xFF8E423E);

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select((ViewModel vm) => vm.isLoading);

    if (isLoading) {
      return Card(
        margin: const EdgeInsets.all(8),
        color: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final data = context.select((ViewModel vm) => vm.nutritionData);

    if (data.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(8),
        color: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('Data is empty')),
        ),
      );
    }

    final maxY = data.map((e) => e.totalGrams).reduce(max) * 1.1;

    return Card(
      margin: const EdgeInsets.all(8),
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24),
        child: Column(
          spacing: 16,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Macronutrients',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Expanded(
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    drawHorizontalLine: true,
                    checkToShowHorizontalLine: (value) => value % 50 == 0,
                    horizontalInterval: 50,
                    getDrawingHorizontalLine: (value) =>
                        const FlLine(color: Colors.white24, strokeWidth: 1.5),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: 50,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}g',
                          style: TextStyle(
                            color: value < (maxY * .999) ? Colors.white54 : Colors.transparent,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= data.length) {
                            return const Text('');
                          }
                          final date = data[value.toInt()].date;
                          return Text(
                            '${date.value.day}\n${getMonthTitle(date.value.month)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: data.asMap().entries.map((entry) {
                    final day = entry.value;
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        // Один столбец с тремя сегментами, сложенными в стек
                        BarChartRodData(
                          toY: day.totalGrams,
                          width: 15,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            topRight: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                            bottomRight: Radius.circular(3),
                          ),
                          rodStackItems: [
                            // Белки — нижний сегмент
                            BarChartRodStackItem(0, day.protein, _proteinColor),
                            // Жиры — средний сегмент
                            BarChartRodStackItem(day.protein, day.protein + day.fat, _fatColor),
                            // Углеводы — верхний сегмент
                            BarChartRodStackItem(day.protein + day.fat, day.totalGrams, _carbsColor),
                          ],
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            // Легенда
            const Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _LegendDot(color: _proteinColor, label: 'Protein'),
                _LegendDot(color: _fatColor, label: 'Fats'),
                _LegendDot(color: _carbsColor, label: 'Carbs'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Точка легенды — цветной кружок с подписью.
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }
}
