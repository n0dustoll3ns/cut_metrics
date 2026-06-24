import 'package:cut_metrics/domain.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class StepsChart extends StatelessWidget {
  final List<StepsDay> data;
  final double targetSteps;
  const StepsChart({required this.data, required this.targetSteps});

  @override
  Widget build(BuildContext context) {
    int maxSteps = data.map((e) => e.steps).reduce((a, b) => a > b ? a : b);
    //TODO добавить горизонтальный пунктир на графике для отметки целевого количества шагов [targetSteps]
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          horizontalInterval: maxSteps * 1.15,
          checkToShowHorizontalLine: (value) => value % 2000 == 0,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.white24, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                '${(value / 1000).toStringAsFixed(0)} K',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= data.length) return const Text('');
                final date = data[value.toInt()].date;
                return Text(
                  '${date.day}\n${getMonthTitle(date.month)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: data
            .map(
              (day) => BarChartGroupData(
                x: day.steps,
                barRods: [
                  BarChartRodData(
                    toY: day.steps.toDouble(),
                    color: Theme.of(context).primaryColor,
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
