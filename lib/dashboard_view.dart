import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cut_metrics/ui/weight/vm.dart';
import 'package:cut_metrics/ui/food/vm.dart';
import 'package:cut_metrics/ui/sleep/vm.dart';
import 'package:cut_metrics/domain/weight.dart';
import 'package:cut_metrics/domain/nutrition.dart';
import 'package:cut_metrics/domain.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  int _selectedDays = 7;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Загружаем данные для всех VM при инициализации
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onDaysChanged(int days) {
    setState(() {
      _selectedDays = days;
    });
    context.read<WeightViewModel>().setSelectedDays(days);
    context.read<NutritionViewModel>().setSelectedDays(days);
    context.read<SleepViewModel>().setSelectedDays(days);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Верхняя панель с навигацией по дням
        _buildTimeNavigation(),

        // Три графика
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(children: [_buildWeightChart(), _buildEnergyBalanceChart(), _buildSleepChart()]),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeNavigation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[900],
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Timeline',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              DropdownButton<int>(
                value: _selectedDays,
                dropdownColor: Colors.grey[850],
                underline: Container(),
                items: const [
                  DropdownMenuItem(
                    value: 7,
                    child: Text('7 days', style: TextStyle(color: Colors.white)),
                  ),
                  DropdownMenuItem(
                    value: 14,
                    child: Text('14 days', style: TextStyle(color: Colors.white)),
                  ),
                  DropdownMenuItem(
                    value: 30,
                    child: Text('30 days', style: TextStyle(color: Colors.white)),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) _onDaysChanged(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Горизонтальный скролл с датами
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedDays,
              itemBuilder: (context, index) {
                final date = DateTime.now().subtract(Duration(days: _selectedDays - 1 - index));
                return Container(
                  width: 50,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.day}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getMonthShort(date.month),
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthShort(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildWeightChart() {
    return Consumer2<WeightViewModel, NutritionViewModel>(
      builder: (context, weightVM, nutritionVM, _) {
        final weightData = weightVM.weightData;
        final emaData = weightVM.emaData;
        final isLoading = weightVM.isLoading;

        if (isLoading) {
          return Card(
            margin: EdgeInsets.all(8),
            color: Colors.grey[900],
            child: Padding(
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
                const Text(
                  'Weight & EMA',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: weightData.isEmpty
                      ? const Center(
                          child: Text('No data', style: TextStyle(color: Colors.white54)),
                        )
                      : _buildWeightLineChart(weightData, emaData),
                ),
              ],
            ),
          ),
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
    minWeight -= range * 0.1;
    maxWeight += range * 0.1;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: range / 4,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: Colors.white24, strokeWidth: 1);
          },
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
                  '${date.day}.${date.month}',
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
          // Основная линия веса
          LineChartBarData(
            spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.weight)).toList(),
            isCurved: true,
            color: const Color(0xFF4CAF50),
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(radius: 4, color: const Color(0xFF4CAF50));
              },
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
          // Линия EMA
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

  Widget _buildEnergyBalanceChart() {
    return Consumer<NutritionViewModel>(
      builder: (context, nutritionVM, _) {
        final data = nutritionVM.nutritionData;
        final isLoading = nutritionVM.isLoading;

        if (isLoading) {
          return Card(
            margin: EdgeInsets.all(8),
            color: Colors.grey[900],
            child: Padding(
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
                const Text(
                  'Energy Balance',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: data.isEmpty
                      ? const Center(
                          child: Text('No data', style: TextStyle(color: Colors.white54)),
                        )
                      : _buildEnergyBalanceBarChart(data),
                ),
                const SizedBox(height: 8),
                // Легенда
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: const [
                    LegendItem(color: Color(0xFF4A5DCB), label: 'Protein'),
                    LegendItem(color: Color(0xFFF9C620), label: 'Fats'),
                    LegendItem(color: Color(0xFF8E423E), label: 'Carbs'),
                    LegendItem(color: Color(0xFF2196F3), label: 'Basal'),
                    LegendItem(color: Color(0xFF4CAF50), label: 'Activity'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnergyBalanceBarChart(List<NutritionDay> data) {
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 500,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: Colors.white24, strokeWidth: 1);
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
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
                  '${date.day}.${date.month}',
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

          // Приход энергии (калории из КБЖУ)
          // final calorieBars = [
          //   BarChartGroupData(
          //     x: index,
          //     barRods: [
          //       BarChartRodData(
          //         toY: day.protein * 4, // 4 ккал на грамм белка
          //         color: const Color(0xFF4A5DCB),
          //         width: 8,
          //         borderRadius: const BorderRadius.only(
          //           topLeft: Radius.circular(4),
          //           topRight: Radius.circular(4),
          //         ),
          //       ),
          //       BarChartRodData(
          //         toY: day.fat * 9, // 9 ккал на грамм жира
          //         color: const Color(0xFFF9C620),
          //         width: 8,
          //         borderRadius: const BorderRadius.only(
          //           topLeft: Radius.circular(4),
          //           topRight: Radius.circular(4),
          //         ),
          //       ),
          //       BarChartRodData(
          //         toY: day.carbs * 4, // 4 ккал на грамм углеводов
          //         color: const Color(0xFF8E423E),
          //         width: 8,
          //         borderRadius: const BorderRadius.only(
          //           topLeft: Radius.circular(4),
          //           topRight: Radius.circular(4),
          //         ),
          //       ),
          //     ],
          //     barsSpace: 2,
          //   ),
          // ];

          return BarChartGroupData(
            x: index,
            barRods: [
              // Столбец прихода (положительный)
              BarChartRodData(
                toY: day.calories,
                color: Colors.blue,
                width: 12,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              // Столбец расхода (отрицательный, показываем вниз от оси X или рядом)
              BarChartRodData(
                toY: -day.totalEnergyExpenditure,
                color: Colors.red.withValues(alpha: 0.7),
                width: 12,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ],
            barsSpace: 4,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSleepChart() {
    return Consumer<SleepViewModel>(
      builder: (context, sleepVM, _) {
        final data = sleepVM.sleepData;
        final isLoading = sleepVM.isLoading;

        if (isLoading) {
          return Card(
            margin: EdgeInsets.all(8),
            color: Colors.grey[900],
            child: Padding(
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
                const Text(
                  'Sleep Phases',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: data.isEmpty
                      ? const Center(
                          child: Text('No data', style: TextStyle(color: Colors.white54)),
                        )
                      : _buildSleepStackedBarChart(data),
                ),
                const SizedBox(height: 8),
                // Легенда
                const Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    LegendItem(color: Color(0xFF1A237E), label: 'Deep'),
                    LegendItem(color: Color(0xFF3F51B5), label: 'Light'),
                    LegendItem(color: Color(0xFF9FA8DA), label: 'REM'),
                  ],
                ),
              ],
            ),
          ),
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
          getDrawingHorizontalLine: (value) {
            return FlLine(color: Colors.white24, strokeWidth: 1);
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                return Text('${value.toInt()}h', style: const TextStyle(color: Colors.white54, fontSize: 10));
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
                  '${date.day}.${date.month}',
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
