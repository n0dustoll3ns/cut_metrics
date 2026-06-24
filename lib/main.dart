import 'package:cut_metrics/repo/health.dart';
import 'package:cut_metrics/ui/time_nav.dart';
import 'package:flutter/material.dart';
import 'package:cut_metrics/dashboard_view.dart';
import 'package:cut_metrics/view_model.dart';
import 'package:provider/provider.dart';

void main() => runApp(
  MaterialApp(
    theme: ThemeData.dark(
      useMaterial3: true,
    ).copyWith(colorScheme: ColorScheme.dark(primary: Colors.orangeAccent)),
    debugShowCheckedModeBanner: false,
    home: const AppView(),
  ),
);

class AppView extends StatelessWidget {
  const AppView({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ViewModel(repository: HealthRepository()))],
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: TimeNav()),
          body: const DashboardView(),
        );
      },
    );
  }
}
