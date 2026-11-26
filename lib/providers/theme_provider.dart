import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Future<void> _fila = Future<void>.value();
  bool _descartado = false;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    unawaited(_carregarTemaInicial());
  }

  Future<void> _carregarTemaInicial() async {
    try {
      await carregarTema();
    } catch (_) {
      debugPrint('Não foi possível carregar a preferência de aparência.');
    }
  }

  Future<void> _enfileirar(Future<void> Function() operacao) {
    final resultado = _fila.then<void>((_) async {
      if (_descartado) return;
      await operacao();
    });

    _fila = resultado.then<void>(
      (_) {},
      onError: (Object erro, StackTrace stackTrace) {},
    );

    return resultado;
  }

  void _aplicarTema(ThemeMode modo) {
    if (_descartado || _themeMode == modo) return;
    _themeMode = modo;
    notifyListeners();
  }

  Future<void> carregarTema() {
    return _enfileirar(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final temaSalvo = prefs.getString('tema_app');

        final modo = switch (temaSalvo) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };

        _aplicarTema(modo);
      } catch (_) {
        throw const ApiException(
          'Não foi possível carregar a aparência salva. Tente novamente.',
        );
      }
    });
  }

  Future<void> alterarTema(ThemeMode modo) {
    return _enfileirar(() async {
      final valor = switch (modo) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

      try {
        final prefs = await SharedPreferences.getInstance();
        final salvo = await prefs.setString('tema_app', valor);

        if (!salvo) {
          throw const ApiException(
            'Não foi possível salvar a aparência. Tente novamente.',
          );
        }
      } on ApiException {
        rethrow;
      } catch (_) {
        throw const ApiException(
          'Não foi possível salvar a aparência. Tente novamente.',
        );
      }

      _aplicarTema(modo);
    });
  }

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }
}
