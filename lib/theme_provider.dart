import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeData _themeData;
  
  // Lista de temas disponibles
  final List<ThemeData> themes = [
    // Tema Azul (default)
    ThemeData(
      primarySwatch: Colors.blue,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        primary: Colors.blue,
        secondary: Colors.blueAccent,
      ),
    ),
    // Tema Morado
    ThemeData(
      primarySwatch: Colors.purple,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.purple,
        primary: Colors.purple,
        secondary: Colors.purpleAccent,
      ),
    ),
    // Tema Verde
    ThemeData(
      primarySwatch: Colors.green,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        primary: Colors.green,
        secondary: Colors.greenAccent,
      ),
    ),
    // Tema Rojo
    ThemeData(
      primarySwatch: Colors.red,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.red,
        primary: Colors.red,
        secondary: Colors.redAccent,
      ),
    ),
    // Tema Oscuro (nuevo)
    ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.blue,
      scaffoldBackgroundColor: Color(0xFF121212), // Color de fondo oscuro
      cardColor: Color(0xFF1E1E1E), // Color de las tarjetas
      colorScheme: ColorScheme.dark(
        primary: Colors.blue,
        secondary: Colors.blueAccent,
        surface: Color(0xFF1E1E1E),
        background: Color(0xFF121212),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        onBackground: Colors.white,
      ),
      
    ),
  ];

  ThemeProvider() : _themeData = ThemeData(
    primarySwatch: Colors.blue,
    scaffoldBackgroundColor: Colors.white,
  );

  ThemeData get themeData => _themeData;

  void setTheme(ThemeData theme) {
    _themeData = theme;
    notifyListeners();
  }
}