import 'package:flutter/material.dart';
import 'package:health_widgets/repo/health.dart';
import 'package:health_widgets/ui/food/view.dart';
import 'package:health_widgets/ui/food/vm.dart';
import 'package:health_widgets/ui/sleep/view.dart';
import 'package:health_widgets/ui/sleep/vm.dart';
import 'package:provider/provider.dart';

enum _AppNavigation { sleep, food }

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  final repo = HealthRepository();
  _AppNavigation _navigation = _AppNavigation.food;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SleepViewModel(repo)),
        ChangeNotifierProvider(create: (_) => NutritionViewModel(repo)),
      ],

      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Sleep Analytics'), centerTitle: true),

          body: SafeArea(
            child: switch (_navigation) {
              _AppNavigation.sleep => SleepView(),
              _AppNavigation.food => NutitonView(),
            },
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: _AppNavigation.values
                .map(
                  (e) => switch (e) {
                    _AppNavigation.sleep => BottomNavigationBarItem(
                      icon: Icon(Icons.bed_outlined),
                      label: 'Sleep',
                    ),
                    // TODO: Handle this case.
                    _AppNavigation.food => BottomNavigationBarItem(
                      icon: Icon(Icons.fastfood_outlined),
                      label: 'Nutrition',
                    ),
                  },
                )
                .toList(),
            currentIndex: _AppNavigation.values.indexOf(_navigation),
            selectedItemColor: Colors.blueAccent,
            unselectedItemColor: Colors.blueGrey,
            onTap: (i) => setState(() => _navigation = _AppNavigation.values.elementAt(i)),
          ),
        );
      },
    );
  }
}
