import 'package:cut_metrics/view_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class TimeNav extends StatelessWidget implements PreferredSizeWidget {
  @override
  final Size preferredSize = const Size(double.infinity, 55);

  const TimeNav({super.key});

  @override
  Widget build(BuildContext context) {
    final (start, end) = context.select((ViewModel vm) => (vm.start, vm.end));

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        spacing: 16,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final res = await showDatePicker(
                  context: context,
                  firstDate: end.subtract(const Duration(days: 999)),
                  lastDate: end,
                  currentDate: start,
                );
                if (res != null && context.mounted) {
                  context.read<ViewModel>().setDate(start: res);
                }
              },
              child: Text(DateFormat.yMd().format(start)),
            ),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final res = await showDatePicker(
                  context: context,
                  firstDate: start,
                  lastDate: DateTime.now(),
                  currentDate: end,
                );
                if (res != null && context.mounted) {
                  context.read<ViewModel>().setDate(end: res);
                }
              },
              child: Text(DateFormat.yMd().format(end)),
            ),
          ),
        ],
      ),
    );
  }
}
