import 'package:cut_metrics/repo/health.dart';
import 'package:cut_metrics/ui/log_button.dart';
import 'package:cut_metrics/ui/source_priority_settings.dart';
import 'package:cut_metrics/ui/time_nav.dart';

import 'package:flutter/material.dart';
import 'package:cut_metrics/dashboard_view.dart';
import 'package:cut_metrics/view_model.dart';

import 'package:provider/provider.dart';

// РЕФАКТОРИНГ: флаг переключения между реальным и mock-репозиторием.
// В debug-режиме используется MockHealthRepository (удобно для UI-разработки),
// в release — настоящий HealthRepository.
// Для принудительного включения mock в release: измените на `= true`.

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
          appBar: AppBar(
            title: TimeNav(),
            actions: const [_SourcePriorityButton(), ExportLogsButton()],
          ),
          body: const DashboardView(),
        );
      },
    );
  }
}

/// Кнопка настройки приоритетов источников в AppBar.
class _SourcePriorityButton extends StatelessWidget {
  const _SourcePriorityButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.tune),
      tooltip: 'Приоритеты источников',
      onPressed: () => showSourcePriorityDialog(context),
    );
  }
}

