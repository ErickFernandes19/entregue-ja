import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';
import 'empresa_service.dart';

enum TipoContaAssinatura { empresa, entregador }

class AssinaturaException implements Exception {
  final String mensagem;
  final int? statusCode;

  const AssinaturaException(this.mensagem, {this.statusCode});

  @override
  String toString() => mensagem;
}

class AssinaturaService {
  static Uri get _urlBase => Uri.parse('${ApiConfig.baseUrl}/assinaturas');

  static String? _normalizarToken(String? token) {
    final valor = token?.trim();
    return valor == null || valor.isEmpty ? null : valor;
  }

  static Future<Map<String, String>> _headersAutenticados({
    TipoContaAssinatura? tipoConta,
  }) async {
    String? token;

    if (tipoConta == TipoContaAssinatura.empresa) {
      token = _normalizarToken(await EmpresaService.obterTokenEmpresa());
    } else if (tipoConta == TipoContaAssinatura.entregador) {
      token = _normalizarToken(await AuthService.obterToken());
    } else {
      final tokenEmpresa = _normalizarToken(
        await EmpresaService.obterTokenEmpresa(),
      );
      final tokenEntregador = _normalizarToken(await AuthService.obterToken());

      if (tokenEmpresa != null && tokenEntregador != null) {
        throw const AssinaturaException(
          'Existem duas sessões disponíveis. Selecione o perfil correto para consultar a assinatura.',
          statusCode: 409,
        );
      }

      token = tokenEmpresa ?? tokenEntregador;
    }

    if (token == null) {
      final mensagem = switch (tipoConta) {
        TipoContaAssinatura.empresa =>
          'Faça login como empresa para utilizar esta funcionalidade.',
        TipoContaAssinatura.entregador =>
          'Faça login como entregador para utilizar esta funcionalidade.',
        null => 'Sua sessão não está disponível. Faça login novamente.',
      };

      throw AssinaturaException(mensagem, statusCode: 401);
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> _get(
    String caminho, {
    TipoContaAssinatura? tipoConta,
  }) async {
    final headers = await _headersAutenticados(tipoConta: tipoConta);

    try {
      return await http
          .get(Uri.parse('$_urlBase/$caminho'), headers: headers)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const AssinaturaException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      throw const AssinaturaException(
        'Não foi possível conectar ao servidor. Verifique sua conexão.',
      );
    }
  }

  static dynamic _decodificar(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const AssinaturaException('O servidor retornou dados inválidos.');
    }
  }

  static void _verificarStatus(http.Response response) {
    switch (response.statusCode) {
      case 200:
        return;
      case 401:
        throw const AssinaturaException(
          'Sua sessão expirou ou é inválida. Faça login novamente.',
          statusCode: 401,
        );
      case 403:
        throw const AssinaturaException(
          'Você não tem permissão para acessar esta assinatura.',
          statusCode: 403,
        );
      case 404:
        throw const AssinaturaException(
          'Nenhuma assinatura foi encontrada.',
          statusCode: 404,
        );
      default:
        throw AssinaturaException(
          'Não foi possível consultar as assinaturas (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
    }
  }

  static void _validarTipoConta(
    Map<String, dynamic> dados,
    TipoContaAssinatura? tipoConta,
  ) {
    if (tipoConta == null) return;

    final esperado = tipoConta == TipoContaAssinatura.empresa
        ? 'EMPRESA'
        : 'ENTREGADOR';

    if (dados['tipoConta'] != esperado) {
      throw const AssinaturaException(
        'O servidor retornou dados de um perfil diferente do solicitado.',
      );
    }
  }

  static Future<Map<String, dynamic>?> buscarAtual({
    TipoContaAssinatura? tipoConta,
  }) async {
    final response = await _get('atual', tipoConta: tipoConta);

    if (response.statusCode == 404) {
      return null;
    }

    _verificarStatus(response);

    final dados = _decodificar(response);

    if (dados is! Map<String, dynamic>) {
      throw const AssinaturaException('Formato de assinatura inválido.');
    }

    _validarTipoConta(dados, tipoConta);
    return dados;
  }

  static Future<List<Map<String, dynamic>>> buscarHistorico({
    TipoContaAssinatura? tipoConta,
  }) async {
    final response = await _get('historico', tipoConta: tipoConta);

    _verificarStatus(response);

    final dados = _decodificar(response);

    if (dados is! List) {
      throw const AssinaturaException('Formato de histórico inválido.');
    }

    return dados.map<Map<String, dynamic>>((item) {
      if (item is! Map<String, dynamic>) {
        throw const AssinaturaException('O histórico contém dados inválidos.');
      }

      _validarTipoConta(item, tipoConta);
      return item;
    }).toList();
  }

  static Future<Map<String, dynamic>> buscarConsumo({
    TipoContaAssinatura? tipoConta,
  }) async {
    final response = await _get('consumo', tipoConta: tipoConta);

    _verificarStatus(response);

    final dados = _decodificar(response);

    if (dados is! Map<String, dynamic>) {
      throw const AssinaturaException('Formato de consumo inválido.');
    }

    _validarTipoConta(dados, tipoConta);
    return dados;
  }

  static Future<Map<String, dynamic>> iniciarTesteEssencial() async {
    final headers = await _headersAutenticados(
      tipoConta: TipoContaAssinatura.empresa,
    );

    try {
      final response = await http
          .post(Uri.parse('$_urlBase/teste-essencial'), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 409) {
        throw const AssinaturaException(
          'O teste gratuito não está disponível ou já foi utilizado.',
          statusCode: 409,
        );
      }

      _verificarStatus(response);

      final dados = _decodificar(response);

      if (dados is! Map<String, dynamic>) {
        throw const AssinaturaException(
          'O servidor retornou uma assinatura inválida.',
        );
      }

      _validarTipoConta(dados, TipoContaAssinatura.empresa);
      return dados;
    } on TimeoutException {
      throw const AssinaturaException(
        'O servidor demorou para responder. Consulte sua assinatura antes de tentar novamente.',
      );
    } on http.ClientException {
      throw const AssinaturaException(
        'Não foi possível conectar ao servidor. Consulte sua assinatura antes de tentar novamente.',
      );
    }
  }
}
