import 'package:cut_metrics/domain.dart';
import 'package:cut_metrics/health_dashboard_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

class StepsChart extends StatelessWidget {
  const StepsChart({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.select((ViewModel vm) => vm.stepsData);

    const targetSteps = 12000;

    //TODO добавить горизонтальный пунктир на графике для отметки целевого количества шагов [targetSteps]
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          checkToShowHorizontalLine: (value) => value % 2000 == 0,
          getDrawingHorizontalLine: (value) => FlLine(
            dashArray: [2, 1],
            color: value == targetSteps ? Theme.of(context).primaryColor : Colors.white24,
            strokeWidth: 1,
          ),
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
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: data
            .map(
              (day) => BarChartGroupData(
                x: ,
                barRods: [BarChartRodData(toY: day.steps.toDouble(), color: Theme.of(context).primaryColor)],
              ),
            )
            .toList(),
      ),
    );
  }
}
