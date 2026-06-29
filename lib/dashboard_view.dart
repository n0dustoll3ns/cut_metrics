import 'package:cut_metrics/view_model.dart';
import 'package:cut_metrics/ui/steps_chart.dart';
import 'package:cut_metrics/ui/nutrition_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cut_metrics/domain/weight.dart';
import 'package:cut_metrics/domain.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 380, child: StepsChart()),
          SizedBox(height: 380, child: NutritionChart()),
          _buildWeightChart(),
          _buildSleepChart(),
        ],
      ),
    );
  }

  Widget _buildWeightChart() {
    return Builder(
      builder: (context) {
        final isLoading = context.select((ViewModel vm) => vm.isLoading);
        final weightData = context.select((ViewModel vm) => vm.weightData);
        final emaData = context.select((ViewModel vm) => vm.emaData);

        return _ChartCard(
          title: 'Weight & EMA',
          isLoading: isLoading,
          isEmpty: weightData.isEmpty,
          child: _buildWeightLineChart(weightData, emaData),
        );
      },
    );
  }

  LineChart _buildWeightLineChart(List<WeightDay> data, List<WeightDay> emaData) {
    if (data.isEmpty) return LineChart(LineChartData());

    double minWeight = data.map((e) => e.weight).reduce((a, b) => a < b ? a : b);
    double maxWeight = data.map((e) => e.weight).reduce((a, b) => a > b ? a : b);
    double range = maxWeight - minWeight;
    if (range < 1.0) range = 1.0;
    minWeight -= range * 0.4;
    maxWeight += range * 0.4;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: range / 4,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.white24, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= data.length) return const Text('');
                final date = data[value.toInt()].date;
                return Text(
                  '${date.value.day}.${date.value.month}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.weight)).toList(),
            isCurved: true,
            color: const Color(0xFF4CAF50),
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(radius: 4, color: const Color(0xFF4CAF50)),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [const Color(0xFF4CAF50).withOpacity(0.3), const Color(0xFF4CAF50).withOpacity(0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          if (emaData.isNotEmpty)
            LineChartBarData(
              spots: emaData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.weight)).toList(),
              isCurved: true,
              color: const Color(0xFFFF9800),
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  Widget _buildSleepChart() {
    return Builder(
      builder: (context) {
        final data = context.select((ViewModel vm) => vm.sleepData);
        final isLoading = context.select((ViewModel vm) => vm.isLoading);

        return _ChartCard(
          title: 'Sleep Phases',
          isLoading: isLoading,
          isEmpty: data.isEmpty,
          legend: const [
            LegendItem(color: Color(0xFF1A237E), label: 'Deep'),
            LegendItem(color: Color(0xFF3F51B5), label: 'Light'),
            LegendItem(color: Color(0xFF9FA8DA), label: 'REM'),
          ],
          child: _buildSleepStackedBarChart(data),
        );
      },
    );
  }

  Widget _buildSleepStackedBarChart(List<SleepDay> data) {
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.white24, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}h',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= data.length) return const Text('');
                final date = data[value.toInt()].date;
                return Text(
                  '${date.value.day}.${date.value.month}',
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
          final index = entry.key;
          final day = entry.value;
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: day.deep,
                color: const Color(0xFF1A237E),
                width: 16,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
              BarChartRodData(
                toY: day.deep + day.light,
                color: const Color(0xFF3F51B5),
                width: 16,
                fromY: day.deep,
              ),
              BarChartRodData(
                toY: day.total,
                color: const Color(0xFF9FA8DA),
                width: 16,
                fromY: day.deep + day.light,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
            ],
            barsSpace: 4,
          );
        }).toList(),
      ),
    );
  }
}

// РЕФАКТОРИНГ: общий виджет карточки-графика, устранён copy-paste loading/empty state.
// Графики weight и sleep используют его вместо дублирующегося кода.
class _ChartCard extends StatelessWidget {
  final String title;
  final bool isLoading;
  final bool isEmpty;
  final Widget child;
  final List<Widget>? legend;

  const _ChartCard({
    required this.title,
    required this.isLoading,
    required this.isEmpty,
    required this.child,
    this.legend,
  });

  @override
  Widget build(BuildContext context) {
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

    return Card(
      margin: const EdgeInsets.all(8),
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: isEmpty
                  ? const Center(child: Text('No data', style: TextStyle(color: Colors.white54)))
                  : child,
            ),
            if (legend != null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 8, children: legend!),
            ],
          ],
        ),
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const LegendItem({super.key, required this.color, required this.label});

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