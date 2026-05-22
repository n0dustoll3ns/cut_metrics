import 'package:flutter/material.dart';
import 'package:health_widgets/repo/health.dart';
import 'package:health_widgets/ui/food/vm.dart';
import 'package:health_widgets/ui/sleep/vm.dart';
import 'package:health_widgets/ui/weight/vm.dart';
import 'package:provider/provider.dart';
import 'dashboard_view.dart';

void main() => runApp(
  MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    debugShowCheckedModeBanner: false,
    home: const AppView(),
  ),
);

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  final repo = HealthRepository();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SleepViewModel(repo)),
        ChangeNotifierProvider(create: (_) => NutritionViewModel(repo)),
        ChangeNotifierProvider(create: (_) => WeightViewModel(repo)),
      ],
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Health Dashboard'),
            centerTitle: true,
          ),
          body: const DashboardView(),
        );
      },
    );
  }
}
