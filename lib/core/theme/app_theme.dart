import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: const Color(0xFF075E54),
        secondary: const Color(0xFF25D366),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF075E54),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF25D366),
        foregroundColor: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF0F2F5),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
