import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class EntregaService {
  static Future<Map<String, dynamic>?> buscarEntrega(String id) async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.entregas}/$id'));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      print('Erro ao buscar entrega. Status: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return null;
    } catch (e) {
      print('Erro ao buscar entrega: $e');
      return null;
    }
  }
}
