import 'dart:math';

import 'package:cut_metrics/domain.dart';
import 'package:cut_metrics/view_model.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

class StepsChart extends StatelessWidget {
  const StepsChart({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select((ViewModel vm) => vm.isLoading);

    if (isLoading) {
      return Card(
        margin: const EdgeInsets.all(8),
        color: Colors.grey[900],
        child: const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final data = context.select((ViewModel vm) => vm.stepsData);

    if (data.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(8),
        color: Colors.grey[900],
        child: const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('Data is empty')),
        ),
      );
    }

    const targetSteps = 12000;

    final maxY = data.map((e) => e.steps).reduce(max).toDouble() * 1.1;
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
              'Steps',
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
                    checkToShowHorizontalLine: (value) => value % 1000 == 0,
                    horizontalInterval: 1000,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: value % 5000 == 0
                          ? Colors.white24
                          : value == targetSteps
                          ? Colors.deepOrange
                          : Colors.transparent,
                      strokeWidth: 1.5,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 5000,
                        getTitlesWidget: (value, meta) => Text(
                          '${(value / 1000).toStringAsFixed(0)} K',
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
                          if (value.toInt() >= data.length) return const Text('');
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
                  barGroups: data
                      .asMap()
                      .entries
                      .map(
                        (entry) => BarChartGroupData(
                          x: entry.key,
                          barRods: [
                            BarChartRodData(
                              toY: entry.value.steps.toDouble(),
                              color: Colors.blueAccent.withValues(alpha: .8),
                              width: 15,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
