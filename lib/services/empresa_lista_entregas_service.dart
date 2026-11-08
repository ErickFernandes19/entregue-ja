import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:entregue_ja/services/empresa_service.dart' as empresa_service;

import '../config/api_config.dart';

class EmpresaListaEntregasService {
  static Future<Map<String, String>> _headersAutenticados() async {
    return await empresa_service.EmpresaService.headersAutenticados();
  }

  static void _registrarErro(String operacao, int statusCode, String body) {
    debugPrint('$operacao: HTTP $statusCode');

    if (statusCode == 401) {
      debugPrint('Sessão da empresa inválida ou token JWT expirado.');
    } else if (statusCode == 403) {
      debugPrint('A empresa não possui permissão para esta operação.');
    } else {
      debugPrint('Resposta: $body');
    }
  }

  static Future<List<dynamic>> buscarEntregas() async {
    try {
      final empresaEmail = await empresa_service.EmpresaService.empresaLogada();

      if (empresaEmail == null || empresaEmail.isEmpty) {
        throw Exception('Empresa não autenticada.');
      }

      final headers = await _headersAutenticados();

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.entregas}/empresa/'
          '${Uri.encodeComponent(empresaEmail)}',
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados is List) {
          return dados;
        }

        throw const FormatException(
          'O servidor não retornou uma lista de entregas.',
        );
      }

      _registrarErro(
        'Erro ao buscar entregas da empresa',
        response.statusCode,
        response.body,
      );

      throw Exception(
        'Falha ao carregar entregas: HTTP ${response.statusCode}',
      );
    } catch (e) {
      debugPrint('Erro ao buscar entregas da empresa: $e');
      rethrow;
    }
  }

  static Future<List<dynamic>> buscarEntregasDoEntregador(
    String entregadorEmail,
  ) async {
    try {
      final empresaEmail = await empresa_service.EmpresaService.empresaLogada();

      if (empresaEmail == null || empresaEmail.isEmpty) {
        throw Exception('Empresa não autenticada.');
      }

      final headers = await _headersAutenticados();

      final empresaEmailUrl = Uri.encodeComponent(empresaEmail);
      final entregadorEmailUrl = Uri.encodeComponent(entregadorEmail);

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.entregas}/empresa/'
          '$empresaEmailUrl/entregador/'
          '$entregadorEmailUrl',
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados is List) {
          return dados;
        }

        throw const FormatException(
          'O servidor não retornou uma lista de entregas.',
        );
      }

      _registrarErro(
        'Erro ao buscar entregas do entregador',
        response.statusCode,
        response.body,
      );

      throw Exception(
        'Falha ao carregar entregas do entregador: '
        'HTTP ${response.statusCode}',
      );
    } catch (e) {
      debugPrint('Erro ao buscar entregas do entregador: $e');
      rethrow;
    }
  }

  static Future<bool> editarEntrega({
    required int id,
    required String cliente,
    required String endereco,
    required double valor,
    required String observacao,
  }) async {
    try {
      final headers = await _headersAutenticados();

      final response = await http.put(
        Uri.parse('${ApiConfig.entregas}/$id'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'cliente': cliente,
          'endereco': endereco,
          'valor': valor,
          'observacao': observacao,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      }

      _registrarErro(
        'Erro ao editar entrega',
        response.statusCode,
        response.body,
      );

      return false;
    } catch (e) {
      debugPrint('Erro ao editar entrega: $e');
      return false;
    }
  }

  static Future<bool> cancelarEntrega(int id) async {
    try {
      final headers = await _headersAutenticados();

      final response = await http.delete(
        Uri.parse('${ApiConfig.entregas}/$id'),
        headers: headers,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }

      _registrarErro(
        'Erro ao cancelar entrega',
        response.statusCode,
        response.body,
      );

      return false;
    } catch (e) {
      debugPrint('Erro ao cancelar entrega: $e');
      return false;
    }
  }
}
