import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'empresa_service.dart';

class PagamentoAssinaturaException implements Exception {
  final String mensagem;
  final int? statusCode;

  const PagamentoAssinaturaException(this.mensagem, {this.statusCode});

  @override
  String toString() => mensagem;
}

class PagamentoAssinaturaService {
  static Uri get _urlBase =>
      Uri.parse('${ApiConfig.baseUrl}/pagamentos/assinaturas');

  static Future<Map<String, String>> _headersAutenticados() async {
    final token = await EmpresaService.obterTokenEmpresa();

    if (token == null || token.trim().isEmpty) {
      throw const PagamentoAssinaturaException(
        'Faça login como empresa para realizar pagamentos.',
        statusCode: 401,
      );
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _processarResposta(http.Response response) {
    switch (response.statusCode) {
      case 200:
        break;
      case 400:
        throw const PagamentoAssinaturaException(
          'Os dados enviados para o pagamento são inválidos.',
          statusCode: 400,
        );
      case 401:
        throw const PagamentoAssinaturaException(
          'Sua sessão expirou. Faça login novamente.',
          statusCode: 401,
        );
      case 403:
        throw const PagamentoAssinaturaException(
          'Apenas empresas podem contratar planos.',
          statusCode: 403,
        );
      case 404:
        throw const PagamentoAssinaturaException(
          'Pagamento não encontrado.',
          statusCode: 404,
        );
      case 409:
        throw const PagamentoAssinaturaException(
          'Não foi possível concluir a operação devido a um conflito. Verifique o pagamento antes de tentar novamente.',
          statusCode: 409,
        );
      case 502:
        throw const PagamentoAssinaturaException(
          'O Mercado Pago não conseguiu processar a solicitação.',
          statusCode: 502,
        );
      default:
        throw PagamentoAssinaturaException(
          'Erro ao processar pagamento (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
    }

    dynamic dados;

    try {
      dados = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PagamentoAssinaturaException(
        'O servidor retornou dados inválidos.',
      );
    }

    if (dados is! Map<String, dynamic>) {
      throw const PagamentoAssinaturaException(
        'Formato de resposta do pagamento inválido.',
      );
    }

    return dados;
  }

  static Future<Map<String, dynamic>> criarPix({
    required String plano,
    required String chaveIdempotencia,
  }) async {
    final headers = await _headersAutenticados();

    try {
      final response = await http
          .post(
            Uri.parse('$_urlBase/pix'),
            headers: headers,
            body: jsonEncode({
              'plano': plano.toUpperCase(),
              'chaveIdempotencia': chaveIdempotencia,
            }),
          )
          .timeout(const Duration(seconds: 30));

      return _processarResposta(response);
    } on TimeoutException {
      throw const PagamentoAssinaturaException(
        'O servidor demorou para responder. A cobrança pode ter sido criada. Consulte o pagamento antes de tentar novamente.',
      );
    } on http.ClientException {
      throw const PagamentoAssinaturaException(
        'Falha de conexão. A cobrança pode ter sido criada. Verifique antes de tentar novamente.',
      );
    }
  }

  static Future<Map<String, dynamic>> consultarPix({
    required int pagamentoId,
  }) async {
    final headers = await _headersAutenticados();

    try {
      final response = await http
          .get(Uri.parse('$_urlBase/pix/$pagamentoId'), headers: headers)
          .timeout(const Duration(seconds: 30));

      return _processarResposta(response);
    } on TimeoutException {
      throw const PagamentoAssinaturaException(
        'O servidor demorou para responder ao consultar o pagamento.',
      );
    } on http.ClientException {
      throw const PagamentoAssinaturaException(
        'Não foi possível consultar o pagamento. Verifique sua conexão.',
      );
    }
  }
}
