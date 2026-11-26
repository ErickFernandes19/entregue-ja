import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

class CepService {
  static const Duration _tempoLimite = Duration(seconds: 12);

  static Future<Map<String, dynamic>?> buscarCep(String cep) async {
    final cepLimpo = cep.trim().replaceAll(RegExp(r'[-\s]'), '');

    if (!RegExp(r'^\d{8}$').hasMatch(cepLimpo)) {
      return null;
    }

    try {
      final response = await http
          .get(Uri.https('viacep.com.br', '/ws/$cepLimpo/json/'))
          .timeout(_tempoLimite);

      if (response.statusCode == 429) {
        throw const ApiException(
          'Muitas consultas de CEP foram realizadas. Aguarde um momento e tente novamente.',
        );
      }

      if (response.statusCode != 200) {
        throw const ApiException(
          'O serviço de consulta de CEP está indisponível. Tente novamente ou preencha o endereço manualmente.',
        );
      }

      final dados = jsonDecode(utf8.decode(response.bodyBytes));

      if (dados is! Map<String, dynamic>) {
        throw const FormatException();
      }

      final erro = dados['erro'];
      if (erro == true || erro?.toString().toLowerCase() == 'true') {
        return null;
      }

      final cepRetornado = dados['cep'];
      final cidade = dados['localidade'];
      final uf = dados['uf'];

      if (cepRetornado is! String ||
          cepRetornado.replaceAll('-', '') != cepLimpo ||
          cidade is! String ||
          cidade.trim().isEmpty ||
          uf is! String ||
          !RegExp(r'^[A-Z]{2}$').hasMatch(uf)) {
        throw const FormatException();
      }

      for (final chave in ['logradouro', 'bairro']) {
        final valor = dados[chave];
        if (valor is! String) {
          throw const FormatException();
        }
      }

      return dados;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'A consulta de CEP demorou para responder. Tente novamente ou preencha o endereço manualmente.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Não foi possível consultar o CEP. Verifique sua conexão com a internet ou preencha o endereço manualmente.',
      );
    } on FormatException {
      throw const ApiException(
        'O serviço de CEP retornou uma resposta inesperada. Tente novamente ou preencha o endereço manualmente.',
      );
    } catch (e) {
      throw ApiException(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível consultar o CEP. Tente novamente ou preencha o endereço manualmente.',
        ),
      );
    }
  }
}
