import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';
import 'empresa_service.dart';

enum TipoContaPagamento { empresa, entregador }

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

  static Future<Map<String, String>> _headersAutenticados(
    TipoContaPagamento tipoConta,
  ) async {
    final token = switch (tipoConta) {
      TipoContaPagamento.empresa => await EmpresaService.obterTokenEmpresa(),
      TipoContaPagamento.entregador => await AuthService.obterToken(),
    };

    if (token == null || token.trim().isEmpty) {
      throw PagamentoAssinaturaException(
        tipoConta == TipoContaPagamento.empresa
            ? 'Faça login como empresa para realizar pagamentos.'
            : 'Faça login como entregador para realizar pagamentos.',
        statusCode: 401,
      );
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${token.trim()}',
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
          'Sua conta não possui permissão para realizar esta operação.',
          statusCode: 403,
        );
      case 404:
        throw const PagamentoAssinaturaException(
          'Pagamento ou assinatura não encontrado.',
          statusCode: 404,
        );
      case 409:
        throw const PagamentoAssinaturaException(
          'Não foi possível concluir a operação devido a um conflito. Verifique suas cobranças e assinaturas existentes antes de tentar novamente.',
          statusCode: 409,
        );
      case 502:
        throw const PagamentoAssinaturaException(
          'O Mercado Pago não conseguiu confirmar a operação. Verifique a situação da cobrança ou assinatura antes de tentar novamente.',
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
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    final headers = await _headersAutenticados(tipoConta);

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
        'O servidor demorou para responder. A cobrança pode ter sido criada. Consulte o pagamento ou recupere a tentativa com a mesma chave antes de gerar outra cobrança.',
      );
    } on http.ClientException {
      throw const PagamentoAssinaturaException(
        'Falha de conexão. A cobrança pode ter sido criada. Recupere a tentativa com a mesma chave antes de gerar outra cobrança.',
      );
    }
  }

  static Future<Map<String, dynamic>> consultarPix({
    required int pagamentoId,
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    final headers = await _headersAutenticados(tipoConta);

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

  static Future<List<Map<String, dynamic>>> listarPixPendentes({
    required TipoContaPagamento tipoConta,
  }) async {
    final headers = await _headersAutenticados(tipoConta);
    final tipoEsperado = switch (tipoConta) {
      TipoContaPagamento.empresa => 'EMPRESA',
      TipoContaPagamento.entregador => 'ENTREGADOR',
    };

    try {
      final response = await http
          .get(Uri.parse('$_urlBase/pix/pendentes'), headers: headers)
          .timeout(const Duration(seconds: 30));

      final dados = _decodificarResposta(response);

      if (dados is! List) {
        throw const PagamentoAssinaturaException(
          'Formato da lista de cobranças Pix inválido.',
        );
      }

      final pagamentos = <Map<String, dynamic>>[];
      final identificadores = <int>{};

      for (final item in dados) {
        if (item is! Map<String, dynamic>) {
          throw const PagamentoAssinaturaException(
            'O servidor retornou uma cobrança Pix inválida.',
          );
        }

        final id = item['pagamentoId'];
        final plano = item['plano'];
        final valor = item['valor'];
        final status = item['status'];

        if (id is! int ||
            id <= 0 ||
            !identificadores.add(id) ||
            item['tipoConta'] != tipoEsperado ||
            (plano != 'ESSENCIAL' && plano != 'PROFISSIONAL') ||
            valor is! num ||
            !valor.isFinite ||
            valor <= 0 ||
            (status != 'PENDENTE' && status != 'APROVADO') ||
            item['planoAtivado'] != false ||
            item['requerConciliacao'] != true) {
          throw const PagamentoAssinaturaException(
            'Não foi possível validar as cobranças Pix pendentes com segurança.',
          );
        }

        pagamentos.add(item);
      }

      return pagamentos;
    } on TimeoutException {
      throw const PagamentoAssinaturaException(
        'O servidor demorou para listar as cobranças Pix. Tente consultar novamente antes de gerar outra cobrança.',
      );
    } on http.ClientException {
      throw const PagamentoAssinaturaException(
        'Não foi possível listar as cobranças Pix. Verifique sua conexão antes de gerar outra cobrança.',
      );
    }
  }

  static Future<Map<String, dynamic>> criarAssinaturaRecorrente({
    required String plano,
    required String chaveIdempotencia,
    required String emailPagador,
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    final email = emailPagador.trim();

    if (email.isEmpty ||
        email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const PagamentoAssinaturaException(
        'Informe um e-mail válido para o responsável pelo pagamento.',
      );
    }

    final headers = await _headersAutenticados(tipoConta);
    headers['X-Idempotency-Key'] = chaveIdempotencia;

    try {
      final response = await http
          .post(
            Uri.parse('$_urlBase/recorrentes'),
            headers: headers,
            body: jsonEncode({
              'plano': plano.toUpperCase(),
              'emailPagador': email,
            }),
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
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    final headers = await _headersAutenticados(tipoConta);

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

  static Future<List<Map<String, dynamic>>> listarAssinaturasRecorrentes({
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    final headers = await _headersAutenticados(tipoConta);

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
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    final headers = await _headersAutenticados(tipoConta);

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
