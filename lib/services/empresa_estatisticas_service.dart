import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:entregue_ja/services/empresa_service.dart' as empresa_service;

import '../config/api_config.dart';

class EmpresaEstatisticasService {
  static Future<Map<String, dynamic>?> buscarEstatisticas() async {
    try {
      final empresaEmail = await empresa_service.EmpresaService.empresaLogada();

      if (empresaEmail == null || empresaEmail.isEmpty) {
        debugPrint('Erro ao buscar estatísticas: empresa não autenticada.');
        return null;
      }

      final headers =
          await empresa_service.EmpresaService.headersAutenticados();

      final empresaEmailUrl = Uri.encodeComponent(empresaEmail);

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.entregas}/estatisticas/empresa/$empresaEmailUrl',
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados is Map<String, dynamic>) {
          debugPrint('Estatísticas carregadas: $dados');
          return dados;
        }

        debugPrint('Erro: formato inesperado das estatísticas.');
        return null;
      }

      if (response.statusCode == 401) {
        debugPrint('Erro 401: sessão empresarial inválida ou expirada.');
      } else if (response.statusCode == 403) {
        debugPrint('Erro 403: acesso às estatísticas negado.');
      } else {
        debugPrint('Erro ao buscar estatísticas: HTTP ${response.statusCode}');
        debugPrint('Resposta: ${response.body}');
      }

      return null;
    } catch (e) {
      debugPrint('Erro ao buscar estatísticas: $e');
      return null;
    }
  }
}
