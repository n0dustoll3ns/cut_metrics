import 'package:flutter/material.dart';
import 'package:health_widgets/widgets/main_screen.dart';
// Полезно для группировки

void main() => runApp(
  MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    debugShowCheckedModeBanner: false,
    home: const MainScreen(),
  ),
);
