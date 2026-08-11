import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/repo/health_repository_impl.dart';
import 'package:cut_metrics/ui/dashboard_view.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/today_screen.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:provider/provider.dart';

void main() => runApp(const CutMetricsApp());

/// Корневой виджет приложения.
///
/// Настраивает Provider с [DashboardViewModel], тему дизайн-системы,
/// и нижнюю навигацию между "Сегодня" и "Дашборд".
class CutMetricsApp extends StatelessWidget {
  const CutMetricsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DashboardViewModel>(
          create: (_) {
            final health = Health();
            return DashboardViewModel(
              repository: HealthRepositoryImpl(
                health: health,
                appPackageId: 'com.example.cut_metrics',
              ),
              processor: HealthDataProcessor(appPackageId: 'com.example.cut_metrics'),
              health: health,
            );
          },
        ),
      ],
      child: MaterialApp(
        title: 'Cut Metrics',
        debugShowCheckedModeBanner: false,
        theme: cmTheme(),
        home: const _AppShell(),
      ),
    );
  }
}

/// Оболочка с нижней навигацией: "Сегодня" и "Дашборд".
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _currentIndex = 0;

  final _screens = const [
    TodayScreen(),
    DashboardView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Сегодня',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Дашборд',
          ),
        ],
      ),
    );
  }
}
