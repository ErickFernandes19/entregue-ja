import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_service.dart';
import 'empresa_service.dart';

class EmpresaEntregaService {
  static const Duration _tempoLimite = Duration(seconds: 20);
  static const ApiException _sessaoExpirada = ApiException(
    'Sua sessão expirou. Entre novamente na sua conta.',
    statusCode: 401,
  );

  static Future<Map<String, String>> _headersAutenticados({
    String? empresaEmail,
  }) async {
    final email = await EmpresaService.empresaLogada();
    if (email == null || email.trim().isEmpty) {
      throw _sessaoExpirada;
    }

    if (empresaEmail != null &&
        email.trim().toLowerCase() != empresaEmail.trim().toLowerCase()) {
      throw const ApiException(
        'Sua sessão foi alterada. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }

    final headers = await EmpresaService.headersAutenticados();
    final autorizacao = headers['Authorization'] ?? '';
    if (!autorizacao.startsWith('Bearer ') ||
        autorizacao.substring(7).trim().isEmpty) {
      throw _sessaoExpirada;
    }

    final emailAtual = await EmpresaService.empresaLogada();
    final tokenAtual = await EmpresaService.obterTokenEmpresa();
    if (emailAtual != email ||
        tokenAtual == null ||
        autorizacao != 'Bearer $tokenAtual') {
      throw _sessaoExpirada;
    }

    return {...headers, 'Content-Type': 'application/json'};
  }

  static ApiException _erroResposta(http.Response response) {
    return ApiService.erroHttp(
      response.statusCode,
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
  }

  static ApiException _converterErro(Object erro, String mensagemPadrao) {
    if (erro is ApiException) return erro;
    if (erro is TimeoutException) {
      return const ApiException(
        'O servidor demorou para responder. Não foi possível confirmar a operação.',
      );
    }
    return ApiException(
      ApiService.mensagemErro(erro, mensagemPadrao: mensagemPadrao),
    );
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
    bool lancarErro = true,
  }) async {
    try {
      final emailEmpresa = empresaEmail.trim();
      final emailEntregador = entregadorEmail?.trim();
      if (emailEmpresa.isEmpty) {
        throw _sessaoExpirada;
      }
      if (cliente.trim().isEmpty || endereco.trim().isEmpty) {
        throw const ApiException('Informe o cliente e o endereço da entrega.');
      }
      if (!valor.isFinite) {
        throw const ApiException('Informe um valor válido para a entrega.');
      }
      if ((latitude == null) != (longitude == null) ||
          (latitude != null &&
              (!latitude.isFinite || latitude < -90 || latitude > 90)) ||
          (longitude != null &&
              (!longitude.isFinite || longitude < -180 || longitude > 180)) ||
          (latitude == 0 && longitude == 0)) {
        throw const ApiException(
          'Não foi possível validar as coordenadas do endereço.',
        );
      }

      final headers = await _headersAutenticados(empresaEmail: emailEmpresa);
      final empresaEmailUrl = Uri.encodeComponent(emailEmpresa);
      final url = emailEntregador != null && emailEntregador.isNotEmpty
          ? '${ApiConfig.entregas}/empresa/$empresaEmailUrl/entregador/${Uri.encodeComponent(emailEntregador)}'
          : '${ApiConfig.entregas}/empresa/$empresaEmailUrl';

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
          .timeout(_tempoLimite);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw _erroResposta(response);
      }

      final dados = jsonDecode(utf8.decode(response.bodyBytes));
      if (dados is! Map<String, dynamic>) {
        throw const FormatException('Formato inválido da entrega cadastrada.');
      }
      final id = int.tryParse(dados['id']?.toString() ?? '');
      if (id == null || id <= 0) {
        throw const FormatException('Identificador da entrega inválido.');
      }
      return dados;
    } catch (e) {
      if (lancarErro) {
        throw _converterErro(e, 'Não foi possível cadastrar a entrega.');
      }
      return null;
    }
  }

  static Future<bool> atribuirEntregador({
    required int entregaId,
    required String entregadorEmail,
    bool lancarErro = false,
  }) async {
    try {
      final email = entregadorEmail.trim();
      if (entregaId <= 0) {
        throw const ApiException('Não foi possível identificar a entrega.');
      }
      if (email.isEmpty) {
        throw const ApiException('Selecione um entregador válido.');
      }

      final headers = await _headersAutenticados();
      final url = '${ApiConfig.entregas}/$entregaId/atribuir-entregador';
      final response = await http
          .put(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode({'entregadorEmail': email}),
          )
          .timeout(_tempoLimite);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw _erroResposta(response);
      }
      return true;
    } catch (e) {
      if (lancarErro) {
        throw _converterErro(e, 'Não foi possível atribuir o entregador.');
      }
      return false;
    }
  }
}
