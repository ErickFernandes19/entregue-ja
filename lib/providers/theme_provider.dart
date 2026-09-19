import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    carregarTema();
  }

  Future<void> carregarTema() async {
    final prefs = await SharedPreferences.getInstance();

    final temaSalvo = prefs.getString('tema_app');

    switch (temaSalvo) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
    }

    notifyListeners();
  }

  Future<void> alterarTema(ThemeMode modo) async {
    _themeMode = modo;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();

    String valor;

    switch (modo) {
      case ThemeMode.light:
        valor = 'light';
        break;
      case ThemeMode.dark:
        valor = 'dark';
        break;
      case ThemeMode.system:
        valor = 'system';
        break;
    }

    await prefs.setString('tema_app', valor);
  }
}
