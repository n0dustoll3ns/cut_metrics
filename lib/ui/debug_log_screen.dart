import 'package:cut_metrics/services/debug_log.dart';
import 'package:cut_metrics/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Экран журнала отладки — «консоль» приложения для release-сборок.
///
/// Показывает записи [DebugLog] (in-memory за сессию, при перезапуске пуст),
/// список обновляется живьём, новые записи сверху. Фильтры: чипы по тегам
/// (`app`/`vm`/`repo`/`perm`) и «Только ошибки». «Копировать всё» кладёт весь
/// журнал в буфер обмена — удобно переслать для разбора.
///
/// Вход скрытый: 5 тапов по подписи версии внизу «Настроек»
/// (см. `_VersionLabel` в `settings_screen.dart`) — работает и в release.
class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  /// Выбранные теги для фильтра (пусто = показывать все теги).
  final Set<String> _selectedTags = {};

  /// Показывать только записи уровня error.
  bool _errorsOnly = false;

  /// Отфильтрованные записи, новые сверху.
  List<DebugLogEntry> get _filtered {
    return DebugLog.instance.entries
        .where((e) =>
            (_selectedTags.isEmpty || _selectedTags.contains(e.tag)) &&
            (!_errorsOnly || e.level == DebugLogLevel.error))
        .toList()
        .reversed
        .toList();
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(
      ClipboardData(text: DebugLog.instance.copyAllText()),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Журнал скопирован в буфер обмена'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    return Scaffold(
      appBar: AppBar(
        title: Text('Журнал отладки', style: CMFonts.heading(size: 19, color: colors.ink)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Копировать всё',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Очистить',
            onPressed: () => DebugLog.instance.clear(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: DebugLog.instance,
        builder: (context, _) {
          final entries = _filtered;
          final colors = context.cmColors;
          final tags = DebugLog.instance.entries
              .map((e) => e.tag)
              .toSet()
              .toList()
            ..sort();
          return Column(
            children: [
              _buildFilters(tags, colors),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          _errorsOnly || _selectedTags.isNotEmpty
                              ? 'Ничего не найдено'
                              : 'Журнал пуст',
                          style: CMFonts.body(size: 14, color: colors.inkMuted),
                        ),
                      )
                    : SelectionArea(
                        child: ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: colors.outline),
                          itemBuilder: (context, i) =>
                              _EntryTile(entry: entries[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilters(List<String> tags, CMThemeColors colors) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: CMSpacing.sp4,
        vertical: CMSpacing.sp2,
      ),
      child: Row(
        children: [
          for (final tag in tags)
            Padding(
              padding: const EdgeInsets.only(right: CMSpacing.sp2),
              child: FilterChip(
                label: Text(
                  tag,
                  style: CMFonts.caption(size: 12, color: colors.ink),
                ),
                selected: _selectedTags.contains(tag),
                onSelected: (value) => setState(() {
                  value ? _selectedTags.add(tag) : _selectedTags.remove(tag);
                }),
              ),
            ),
          FilterChip(
            avatar: const Icon(Icons.error_outline, size: 16),
            label: const Text('Только ошибки'),
            selected: _errorsOnly,
            onSelected: (value) => setState(() => _errorsOnly = value),
          ),
        ],
      ),
    );
  }
}

/// Одна запись журнала: строка времени+тега (Space Mono, Noise Grey) и
/// сообщение (Space Mono). warn — Signal Cobalt, error — Alert Rust, полужирный.
class _EntryTile extends StatelessWidget {
  final DebugLogEntry entry;

  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.cmColors;
    final (color, bold) = switch (entry.level) {
      DebugLogLevel.info => (colors.ink, false),
      DebugLogLevel.warn => (colors.signal, true),
      DebugLogLevel.error => (colors.alert, true),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CMSpacing.sp4,
        vertical: CMSpacing.sp3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DebugLog.formatTime(entry.time)}  [${entry.tag}]',
            style: CMFonts.caption(size: 11, color: colors.noise),
          ),
          const SizedBox(height: CMSpacing.sp1),
          Text(
            entry.message,
            style: CMFonts.caption(size: 12, color: color).copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
