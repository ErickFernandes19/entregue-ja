import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

class AssinaturaException implements Exception {
  final String mensagem;
  final int? statusCode;

  const AssinaturaException(this.mensagem, {this.statusCode});

  @override
  String toString() => mensagem;
}

class AssinaturaService {
  static Uri get _urlBase => Uri.parse('${ApiConfig.baseUrl}/assinaturas');

  static Future<http.Response> _get(String caminho) async {
    final token = await AuthService.obterToken();

    if (token == null || token.trim().isEmpty) {
      throw const AssinaturaException(
        'Sua sessão não está disponível. Faça login novamente.',
        statusCode: 401,
      );
    }

    try {
      return await http
          .get(
            Uri.parse('$_urlBase/$caminho'),
            headers: await AuthService.headersAutenticados(),
          )
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

  static Future<Map<String, dynamic>?> buscarAtual() async {
    final response = await _get('atual');

    if (response.statusCode == 404) {
      return null;
    }

    _verificarStatus(response);
    final dados = _decodificar(response);

    if (dados is! Map<String, dynamic>) {
      throw const AssinaturaException('Formato de assinatura inválido.');
    }

    return dados;
  }

  static Future<List<Map<String, dynamic>>> buscarHistorico() async {
    final response = await _get('historico');
    _verificarStatus(response);
    final dados = _decodificar(response);

    if (dados is! List) {
      throw const AssinaturaException('Formato de histórico inválido.');
    }

    try {
      return dados
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } on TypeError {
      throw const AssinaturaException('O histórico contém dados inválidos.');
    }
  }

  static Future<Map<String, dynamic>> buscarConsumo() async {
    final response = await _get('consumo');
    _verificarStatus(response);
    final dados = _decodificar(response);

    if (dados is! Map<String, dynamic>) {
      throw const AssinaturaException('Formato de consumo inválido.');
    }

    return dados;
  }
}
