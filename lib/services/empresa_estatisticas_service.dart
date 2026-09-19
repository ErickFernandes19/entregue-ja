import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:entregue_ja/services/empresa_service.dart' as empresa_service;

import '../config/api_config.dart';

class EmpresaEstatisticasService {
  static Future<Map<String, dynamic>?> buscarEstatisticas() async {
    try {
      final empresaEmail = await empresa_service.EmpresaService.empresaLogada();

      if (empresaEmail == null) {
        return null;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.entregas}/estatisticas/empresa/$empresaEmail'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      print('Erro ao buscar estatísticas. Status: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return null;
    } catch (e) {
      print('Erro estatísticas: $e');
      return null;
    }
  }
}
