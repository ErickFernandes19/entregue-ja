import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_service.dart';
import 'auth_service.dart';

class LocalizacaoEntregadorService {
  static const Duration _intervalo = Duration(seconds: 15);
  static const double _precisaoMaximaMetros = 100;

  Timer? _timer;
  String? _email;
  String? _token;
  int _geracao = 0;
  bool _executando = false;
  bool _descartado = false;

  void iniciar({required String email, required String token}) {
    if (_descartado || email.trim().isEmpty || token.trim().isEmpty) return;
    if (_timer?.isActive == true && _email == email && _token == token) {
      return;
    }

    parar();
    _email = email;
    _token = token;
    final geracao = _geracao;
    _timer = Timer.periodic(_intervalo, (_) {
      unawaited(_atualizar(geracao));
    });
    unawaited(_atualizar(geracao));
  }

  void parar() {
    _geracao++;
    _timer?.cancel();
    _timer = null;
    _email = null;
    _token = null;
  }

  bool _ativo(int geracao) =>
      !_descartado && geracao == _geracao && _timer?.isActive == true;

  Future<bool> _sessaoValida(int geracao) async {
    if (!_ativo(geracao)) return false;
    final email = await AuthService.usuarioLogado();
    final token = await AuthService.obterToken();
    if (!_ativo(geracao)) return false;
    if (email == null || email != _email || token == null || token != _token) {
      parar();
      return false;
    }
    return true;
  }

  Future<void> _atualizar(int geracao) async {
    if (!_ativo(geracao) || _executando) return;
    _executando = true;

    try {
      if (!await _sessaoValida(geracao)) return;
      final email = _email!;
      final entregas = await ApiService.buscarEntregasDoEntregador(email);
      if (!await _sessaoValida(geracao)) return;

      final ids = <int>{};
      for (final entrega in entregas) {
        if (entrega is! Map) continue;
        final status = entrega['status']?.toString().trim().toUpperCase();
        final id = int.tryParse(entrega['id']?.toString() ?? '');
        if (status == 'EM_ROTA' && id != null && id > 0) {
          ids.add(id);
        }
      }

      if (ids.isEmpty) {
        parar();
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('Acompanhamento: serviço de localização desativado.');
        return;
      }
      if (!_ativo(geracao)) return;

      final permissao = await Geolocator.checkPermission();
      if (permissao != LocationPermission.whileInUse &&
          permissao != LocationPermission.always) {
        debugPrint('Acompanhamento: permissão de localização indisponível.');
        return;
      }
      if (!_ativo(geracao)) return;

      final posicao = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!_ativo(geracao)) return;

      final idade = DateTime.now().difference(posicao.timestamp);
      if (!posicao.latitude.isFinite ||
          !posicao.longitude.isFinite ||
          posicao.latitude < -90 ||
          posicao.latitude > 90 ||
          posicao.longitude < -180 ||
          posicao.longitude > 180 ||
          (posicao.latitude == 0 && posicao.longitude == 0) ||
          !posicao.accuracy.isFinite ||
          posicao.accuracy < 0 ||
          posicao.accuracy > _precisaoMaximaMetros ||
          idade > const Duration(seconds: 30) ||
          idade < const Duration(seconds: -5)) {
        debugPrint('Acompanhamento: leitura GPS inválida ou imprecisa.');
        return;
      }

      for (final id in ids) {
        if (!await _sessaoValida(geracao)) return;
        if (DateTime.now().difference(posicao.timestamp) >
            const Duration(seconds: 30)) {
          return;
        }
        final sucesso = await ApiService.enviarLocalizacaoEntregador(
          id: id,
          latitude: posicao.latitude,
          longitude: posicao.longitude,
        );
        if (!_ativo(geracao)) return;
        if (!sucesso) {
          debugPrint('Acompanhamento: envio não confirmado para entrega #$id.');
        }
      }
    } catch (e) {
      if (_ativo(geracao)) {
        debugPrint('Não foi possível atualizar o acompanhamento: $e');
      }
    } finally {
      _executando = false;
    }
  }

  void dispose() {
    _descartado = true;
    parar();
  }
}
