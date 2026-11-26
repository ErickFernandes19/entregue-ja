import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_service.dart';
import 'empresa_service.dart';

class EmpresaEstatisticasService {
  static const Duration _tempoLimite = Duration(seconds: 15);

  static Future<Map<String, dynamic>?> buscarEstatisticas() async {
    try {
      final empresaEmail = await EmpresaService.empresaLogada();

      if (empresaEmail == null || empresaEmail.trim().isEmpty) {
        throw const ApiException(
          'Sua sessão expirou. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }

      final headers = await EmpresaService.headersAutenticados();
      final autorizacao = headers['Authorization'] ?? '';

      if (!autorizacao.startsWith('Bearer ') ||
          autorizacao.substring(7).trim().isEmpty) {
        throw const ApiException(
          'Sua sessão expirou. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }

      final empresaEmailUrl = Uri.encodeComponent(empresaEmail);
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.entregas}/estatisticas/empresa/$empresaEmailUrl',
            ),
            headers: headers,
          )
          .timeout(_tempoLimite);

      if (response.statusCode != 200) {
        throw ApiService.erroHttp(response.statusCode, response.body);
      }

      final dados = jsonDecode(utf8.decode(response.bodyBytes));

      if (dados is! Map<String, dynamic>) {
        throw const FormatException('Formato inválido das estatísticas.');
      }

      const campos = [
        'total',
        'entregues',
        'pendentes',
        'emRota',
        'naoEntregues',
      ];

      final estatisticas = Map<String, dynamic>.from(dados);

      for (final campo in campos) {
        final valor = int.tryParse(estatisticas[campo]?.toString() ?? '');

        if (valor == null || valor < 0) {
          throw const FormatException('Valor inválido nas estatísticas.');
        }

        estatisticas[campo] = valor;
      }

      return estatisticas;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'O servidor demorou para responder. Tente atualizar as estatísticas novamente.',
      );
    } catch (e) {
      throw ApiException(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível carregar as estatísticas. Tente novamente.',
        ),
      );
    }
  }
}
