import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';
import 'empresa_service.dart' as empresa_service;

class GeocodingService {
  static Future<Map<String, String>> _headersAutenticados() async {
    // Primeiro verifica se existe uma sessão de entregador.
    final tokenEntregador = await AuthService.obterToken();

    if (tokenEntregador != null && tokenEntregador.isNotEmpty) {
      return AuthService.headersAutenticados();
    }

    // Caso contrário, utiliza a autenticação da empresa.
    return empresa_service.EmpresaService.headersAutenticados();
  }

  static Future<Map<String, double>?> buscarCoordenadas(String endereco) async {
    try {
      final enderecoLimpo = endereco.trim();

      if (enderecoLimpo.isEmpty) {
        return null;
      }

      final headers = await _headersAutenticados();

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/rotas/geocodificar',
      ).replace(queryParameters: {'endereco': enderecoLimpo});

      debugPrint('Buscando coordenadas para: $enderecoLimpo');

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('Geocodificação HTTP: ${response.statusCode}');

      if (response.statusCode == 401) {
        debugPrint('Sessão inválida ou token JWT expirado.');
        return null;
      }

      if (response.statusCode == 403) {
        debugPrint('Usuário sem permissão para geocodificação.');
        return null;
      }

      if (response.statusCode != 200) {
        debugPrint(
          'Falha na geocodificação: '
          'HTTP ${response.statusCode}',
        );
        return null;
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) {
        debugPrint('Resposta inválida da geocodificação.');
        return null;
      }

      final latitude = data['lat'];
      final longitude = data['lng'];

      if (latitude is! num || longitude is! num) {
        debugPrint('Coordenadas ausentes na resposta.');
        return null;
      }

      final coordenadas = {
        'lat': latitude.toDouble(),
        'lng': longitude.toDouble(),
      };

      debugPrint(
        'Coordenadas encontradas: '
        '${coordenadas['lat']}, '
        '${coordenadas['lng']}',
      );

      return coordenadas;
    } catch (e) {
      debugPrint('Erro ao buscar coordenadas: $e');

      return null;
    }
  }
}
