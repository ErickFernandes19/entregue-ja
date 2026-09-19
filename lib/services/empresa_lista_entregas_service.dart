import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:entregue_ja/services/empresa_service.dart' as empresa_service;

import '../config/api_config.dart';

class EmpresaListaEntregasService {
  static Future<List<dynamic>> buscarEntregas() async {
    try {
      final empresaEmail = await empresa_service.EmpresaService.empresaLogada();

      if (empresaEmail == null) {
        return [];
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.entregas}/empresa/$empresaEmail'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      print('Erro ao buscar entregas. Status: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return [];
    } catch (e) {
      print('Erro ao buscar entregas: $e');
      return [];
    }
  }

  static Future<List<dynamic>> buscarEntregasDoEntregador(
    String entregadorEmail,
  ) async {
    try {
      final empresaEmail = await empresa_service.EmpresaService.empresaLogada();

      if (empresaEmail == null || empresaEmail.isEmpty) {
        return [];
      }

      final empresaEmailUrl = Uri.encodeComponent(empresaEmail);

      final entregadorEmailUrl = Uri.encodeComponent(entregadorEmail);

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.entregas}/empresa/'
          '$empresaEmailUrl/entregador/'
          '$entregadorEmailUrl',
        ),
      );

      print('Entregas do entregador status: ${response.statusCode}');

      print('Entregas do entregador body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return [];
    } catch (e) {
      print('Erro ao buscar entregas do entregador: $e');

      return [];
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
      final response = await http.put(
        Uri.parse('${ApiConfig.entregas}/$id'),
        headers: {'Content-Type': 'application/json'},
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

      print('Erro ao editar entrega. Status: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return false;
    } catch (e) {
      print('Erro ao editar entrega: $e');
      return false;
    }
  }

  static Future<bool> cancelarEntrega(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.entregas}/$id'),
      );

      if (response.statusCode == 200) {
        return true;
      }

      print('Erro ao cancelar entrega. Status: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return false;
    } catch (e) {
      print('Erro ao cancelar entrega: $e');
      return false;
    }
  }
}
