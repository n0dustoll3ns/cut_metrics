import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/recommendation_config.dart';
import 'package:cut_metrics/repo/health_repository_impl.dart';
import 'package:cut_metrics/services/debug_log.dart';
import 'package:cut_metrics/services/settings_service.dart';
import 'package:cut_metrics/ui/settings_screen.dart';
import 'package:cut_metrics/ui/summary_screen.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:cut_metrics/ui/today_screen.dart';
import 'package:cut_metrics/ui/trend_screen.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:provider/provider.dart';

void main() {
  DebugLog.instance.log(
    'app',
    'Cut Metrics старт (${kReleaseMode ? 'release' : 'debug'})',
  );
  runApp(const CutMetricsApp());
}

/// Корневой виджет приложения.
///
/// Настраивает Provider с [DashboardViewModel] и [SettingsService], тему
/// дизайн-системы, нижнюю навигацию из 4 вкладок (Фаза 5):
/// Сегодня · Тренд · Саммари · Настройки.
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
              settingsService: SettingsService(),
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

/// Оболочка с нижней навигацией: Сегодня · Тренд · Саммари · Настройки.
///
/// Гейт «Саммари» (U3 + решение №7): вкладка открывается только когда
/// саммари готово (≥3 взвешиваний за последние 7 дней), иначе — снекбар.
/// При открытии фиксируется `lastSummaryShownDate`.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Возврат в приложение (например, после выдачи разрешений в системных
  /// настройках — кнопка на баннере «Сегодня»): тихо перепроверяем права
  /// без диалога; если выданы — данные перезагружаются, баннер исчезает.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<DashboardViewModel>().recheckPermissions();
    }
  }

  void _selectTab(int index) {
    final vm = context.read<DashboardViewModel>();

    if (index == 2) {
      final summary = vm.computeWeeklySummary();
      if (summary == null) {
        // Решение №7: снекбар, вкладка не открывается.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(RecommendationConfig.summaryNotReadyMessage),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // Фиксация показа саммари (хранится, но не гейтит — U3).
      vm.markSummaryShown();
    }

    // «Сегодня» всегда показывает 30-дневный график.
    if (index == 0 && vm.rangeDays != RecommendationConfig.todayChartDays) {
      vm.setRange(RecommendationConfig.todayChartDays);
    }

    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      TodayScreen(onOpenSummary: () => _selectTab(2)),
      const TrendScreen(),
      const SummaryScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Сегодня',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Тренд',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Саммари',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune),
            selectedIcon: Icon(Icons.tune),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}

