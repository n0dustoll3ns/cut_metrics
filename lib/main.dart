import 'package:cut_metrics/repo/health_mock.dart';
import 'package:flutter/material.dart';
import 'package:cut_metrics/dashboard_view.dart';
import 'package:cut_metrics/health_dashboard_viewmodel.dart';
import 'package:provider/provider.dart';

void main() => runApp(
  MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    debugShowCheckedModeBanner: false,
    home: const AppView(),
  ),
);

class AppView extends StatelessWidget {
  const AppView({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => HealthDashboardViewModel(repository: MockHealthRepository())),
      ],
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Health Dashboard'), centerTitle: true),
          body: const DashboardView(),
        );
      },
    );
  }
}
