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

  static void _validarStatus(http.Response response) {
    switch (response.statusCode) {
      case 200:
      case 201:
        return;
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
          'Pagamento ou assinatura não encontrado.',
          statusCode: 404,
        );
      case 409:
        throw const PagamentoAssinaturaException(
          'Não foi possível concluir a operação devido a um conflito. Verifique sua assinatura antes de tentar novamente.',
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
  }

  static dynamic _decodificarResposta(http.Response response) {
    _validarStatus(response);

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PagamentoAssinaturaException(
        'O servidor retornou dados inválidos.',
      );
    }
  }

  static Map<String, dynamic> _processarResposta(http.Response response) {
    final dados = _decodificarResposta(response);

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

  static Future<Map<String, dynamic>> criarAssinaturaRecorrente({
    required String plano,
    required String chaveIdempotencia,
  }) async {
    final headers = await _headersAutenticados();
    headers['X-Idempotency-Key'] = chaveIdempotencia;

    try {
      final response = await http
          .post(
            Uri.parse('$_urlBase/recorrentes'),
            headers: headers,
            body: jsonEncode({'plano': plano.toUpperCase()}),
          )
          .timeout(const Duration(seconds: 30));

      return _processarResposta(response);
    } on TimeoutException {
      throw const PagamentoAssinaturaException(
        'A solicitação demorou para responder. A assinatura pode ter sido criada. Consulte suas assinaturas antes de tentar novamente.',
      );
    } on http.ClientException {
      throw const PagamentoAssinaturaException(
        'Falha de conexão. A assinatura pode ter sido criada. Consulte suas assinaturas antes de tentar novamente.',
      );
    }
  }

  static Future<Map<String, dynamic>> consultarAssinaturaRecorrente({
    required int assinaturaId,
  }) async {
    final headers = await _headersAutenticados();

    try {
      final response = await http
          .get(
            Uri.parse('$_urlBase/recorrentes/$assinaturaId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      return _processarResposta(response);
    } on TimeoutException {
      throw const PagamentoAssinaturaException(
        'O servidor demorou para responder ao consultar a assinatura.',
      );
    } on http.ClientException {
      throw const PagamentoAssinaturaException(
        'Não foi possível consultar a assinatura. Verifique sua conexão.',
      );
    }
  }

  static Future<List<Map<String, dynamic>>>
  listarAssinaturasRecorrentes() async {
    final headers = await _headersAutenticados();

    try {
      final response = await http
          .get(Uri.parse('$_urlBase/recorrentes'), headers: headers)
          .timeout(const Duration(seconds: 30));

      final dados = _decodificarResposta(response);
      if (dados is! List) {
        throw const PagamentoAssinaturaException(
          'Formato da lista de assinaturas inválido.',
        );
      }

      return dados.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const PagamentoAssinaturaException(
            'O servidor retornou uma assinatura inválida.',
          );
        }
        return item;
      }).toList();
    } on TimeoutException {
      throw const PagamentoAssinaturaException(
        'O servidor demorou para listar as assinaturas.',
      );
    } on http.ClientException {
      throw const PagamentoAssinaturaException(
        'Não foi possível listar as assinaturas. Verifique sua conexão.',
      );
    }
  }

  static Future<Map<String, dynamic>> cancelarAssinaturaRecorrente({
    required int assinaturaId,
  }) async {
    final headers = await _headersAutenticados();

    try {
      final response = await http
          .post(
            Uri.parse('$_urlBase/recorrentes/$assinaturaId/cancelar'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));

      return _processarResposta(response);
    } on TimeoutException {
      throw const PagamentoAssinaturaException(
        'O cancelamento pode ter sido solicitado. Consulte a assinatura para confirmar o status.',
      );
    } on http.ClientException {
      throw const PagamentoAssinaturaException(
        'Falha de conexão. Consulte a assinatura para confirmar se o cancelamento ocorreu.',
      );
    }
  }
}
