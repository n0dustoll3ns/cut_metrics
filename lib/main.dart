import 'package:flutter/material.dart';
import 'package:health_widgets/repo/health.dart';
import 'package:health_widgets/viewmodels/health_dashboard_viewmodel.dart';
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
    return ChangeNotifierProvider(
      create: (_) => HealthDashboardViewModel(repository: repo),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Health Dashboard'),
          centerTitle: true,
        ),
        body: const DashboardView(),
      ),
    );
  }
}
