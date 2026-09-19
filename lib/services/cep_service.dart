import 'dart:convert';

import 'package:http/http.dart' as http;

class CepService {
  static Future<Map<String, dynamic>?> buscarCep(String cep) async {
    try {
      final cepLimpo = cep.replaceAll(RegExp(r'[^0-9]'), '');

      if (cepLimpo.length != 8) {
        return null;
      }

      final response = await http.get(
        Uri.parse('https://viacep.com.br/ws/$cepLimpo/json/'),
      );

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados['erro'] == true) {
          return null;
        }

        return dados;
      }

      return null;
    } catch (e) {
      print('Erro ao buscar CEP: $e');
      return null;
    }
  }
}
