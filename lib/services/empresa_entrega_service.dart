import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class EmpresaEntregaService {
  static Future<Map<String, dynamic>?> cadastrarEntrega({
    required String empresaEmail,
    required String entregadorEmail,
    required String cliente,
    required String endereco,
    required double valor,
    required String observacao,
  }) async {
    try {
      final empresaEmailUrl = Uri.encodeComponent(empresaEmail);
      final entregadorEmailUrl = Uri.encodeComponent(entregadorEmail);

      final url =
          '${ApiConfig.entregas}/empresa/$empresaEmailUrl/'
          'entregador/$entregadorEmailUrl';

      print('URL cadastro entrega: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'cliente': cliente,
          'endereco': endereco,
          'valor': valor,
          'observacao': observacao,
        }),
      );

      print('Status cadastro entrega: ${response.statusCode}');
      print('Body cadastro entrega: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return null;
    } catch (e) {
      print('Erro ao cadastrar entrega: $e');
      return null;
    }
  }
}
