import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';
import 'empresa_service.dart' as empresa_service;

class EmpresaEntregaService {
  static Future<Map<String, String>> _headersAutenticados() async {
    final tokenEntregador = await AuthService.obterToken();

    if (tokenEntregador != null && tokenEntregador.isNotEmpty) {
      return AuthService.headersAutenticados();
    }

    return empresa_service.EmpresaService.headersAutenticados();
  }

  static Future<Map<String, dynamic>?> cadastrarEntrega({
    required String empresaEmail,
    String? entregadorEmail,
    required String cliente,
    required String endereco,
    required String complemento,
    required double valor,
    required String observacao,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final empresaEmailUrl = Uri.encodeComponent(empresaEmail);
      final emailEntregador = entregadorEmail?.trim();

      final url = emailEntregador != null && emailEntregador.isNotEmpty
          ? '${ApiConfig.entregas}/empresa/$empresaEmailUrl/entregador/${Uri.encodeComponent(emailEntregador)}'
          : '${ApiConfig.entregas}/empresa/$empresaEmailUrl';

      final headers = await _headersAutenticados();
      headers['Content-Type'] = 'application/json';

      debugPrint('URL cadastro entrega: $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode({
              'cliente': cliente,
              'endereco': endereco,
              'complemento': complemento,
              'valor': valor,
              'observacao': observacao,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(const Duration(seconds: 20));

      debugPrint('Status cadastro entrega: ${response.statusCode}');

      if (response.statusCode == 401) {
        debugPrint('Token JWT ausente, inválido ou expirado.');
        return null;
      }

      if (response.statusCode == 403) {
        debugPrint('Usuário sem permissão para cadastrar entrega.');
        return null;
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        if (data is Map<String, dynamic>) {
          debugPrint('Entrega cadastrada com sucesso!');
          return data;
        }
      }

      debugPrint(
        'Falha ao cadastrar entrega. HTTP ${response.statusCode}: ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Erro ao cadastrar entrega: $e');
      return null;
    }
  }

  static Future<bool> atribuirEntregador({
    required int entregaId,
    required String entregadorEmail,
  }) async {
    try {
      final email = entregadorEmail.trim();
      if (email.isEmpty) return false;

      final headers = await _headersAutenticados();
      headers['Content-Type'] = 'application/json';

      final url = '${ApiConfig.entregas}/$entregaId/atribuir-entregador';
      final response = await http
          .put(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode({'entregadorEmail': email}),
          )
          .timeout(const Duration(seconds: 20));

      debugPrint('Status atribuição de entregador: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }

      debugPrint(
        'Falha ao atribuir entregador. HTTP ${response.statusCode}: ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('Erro ao atribuir entregador: $e');
      return false;
    }
  }
}
