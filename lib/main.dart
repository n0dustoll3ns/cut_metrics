import 'dart:io';

import 'package:cut_metrics/repo/health.dart';
import 'package:cut_metrics/ui/source_priority_settings.dart';
import 'package:cut_metrics/ui/time_nav.dart';
import 'package:external_path/external_path.dart';

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
            actions: const [_SourcePriorityButton(), _ExportLogsButton()],
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

/// Кнопка экспорта логов в AppBar.
/// Создаёт txt-файлы с логами (сырые и обработанные данные) в папке
/// Download/cut_metrics/timestamp/ на устройстве.
class _ExportLogsButton extends StatelessWidget {
  const _ExportLogsButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.file_download_outlined),
      tooltip: 'Export Logs',
      onPressed: () => _exportLogs(context),
    );
  }

  Future<void> _exportLogs(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final vm = context.read<ViewModel>();

    try {
      final logs = vm.buildLogs();

      // Папка для логов: Download/cut_metrics/<timestamp>/
      final baseDir = await _getPublicLogsDirectory();

      if (baseDir == null) {
        messenger.showSnackBar(const SnackBar(content: Text('❌ Не удалось найти папку для записи')));
        return;
      }

      final logsDir = Directory('${baseDir.path}/cut_metrics');
      if (!logsDir.existsSync()) {
        logsDir.createSync(recursive: true);
      }

      final now = DateTime.now();
      final timestamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';

      final subDir = Directory('${logsDir.path}/$timestamp');
      subDir.createSync(recursive: true);

      for (final entry in logs.entries) {
        final file = File('${subDir.path}/${entry.key}');
        file.writeAsStringSync(entry.value);
      }

      messenger.showSnackBar(SnackBar(content: Text('✅ ${logs.length} файлов сохранено в:\n${subDir.path}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ Ошибка экспорта: $e')));
    }
  }

  Future<Directory?> _getPublicLogsDirectory() async {
    String? path = '';

    try {
      // Получаем прямой путь к системной папке "Documents"
      // (обычно это /storage/emulated/0/Documents)
      path = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOCUMENTS);
    } catch (_) {}

    if (path == null) {
      try {
        // Если что-то пошло не так, откатываемся на загрузки
        path = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOWNLOAD);
      } catch (_) {}
    }

    if (path == null) return null;

    // Создаем внутри нашей папки Documents подпапку для своего приложения,
    // чтобы не мусорить в корне
    final appLogsDir = Directory('$path/CutMetricsLogs');

    if (!await appLogsDir.exists()) {
      await appLogsDir.create(recursive: true);
    }

    return appLogsDir;
  }
}
