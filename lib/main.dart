import 'package:flutter/material.dart';
import 'package:health_widgets/view.dart';
// Полезно для группировки

void main() => runApp(
  MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    debugShowCheckedModeBanner: false,
    home: const AppView(),
  ),
);
