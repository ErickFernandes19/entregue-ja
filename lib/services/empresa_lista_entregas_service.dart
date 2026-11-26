import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_service.dart';
import 'empresa_service.dart';

class EmpresaListaEntregasService {
  static const Duration _tempoLimite = Duration(seconds: 15);
  static const ApiException _sessaoExpirada = ApiException(
    'Sua sessão expirou. Entre novamente na sua conta.',
    statusCode: 401,
  );

  static Future<String> _empresaAutenticada() async {
    final email = await EmpresaService.empresaLogada();
    if (email == null || email.trim().isEmpty) {
      throw _sessaoExpirada;
    }
    return email;
  }

  static Future<Map<String, String>> _headersAutenticados() async {
    final headers = await EmpresaService.headersAutenticados();
    final autorizacao = headers['Authorization'] ?? '';
    if (!autorizacao.startsWith('Bearer ') ||
        autorizacao.substring(7).trim().isEmpty) {
      throw _sessaoExpirada;
    }
    return headers;
  }

  static ApiException _erroResposta(http.Response response) {
    return ApiService.erroHttp(
      response.statusCode,
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
  }

  static List<dynamic> _validarEntregas(http.Response response) {
    final dados = jsonDecode(utf8.decode(response.bodyBytes));
    if (dados is! List) {
      throw const FormatException('Formato inválido da lista de entregas.');
    }

    for (final item in dados) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Formato inválido de entrega.');
      }
      final id = int.tryParse(item['id']?.toString() ?? '');
      final valor = item['valor'];
      final entregue = item['entregue'];
      if (id == null ||
          id <= 0 ||
          (valor != null && (valor is! num || !valor.isFinite)) ||
          (entregue != null && entregue is! bool)) {
        throw const FormatException('Dados inválidos de entrega.');
      }
    }

    return dados;
  }

  static Future<List<dynamic>> _buscarEntregas({
    String? entregadorEmail,
  }) async {
    try {
      final empresaEmail = await _empresaAutenticada();
      final headers = await _headersAutenticados();
      final empresaEmailUrl = Uri.encodeComponent(empresaEmail);
      var caminho = '${ApiConfig.entregas}/empresa/$empresaEmailUrl';

      if (entregadorEmail != null) {
        final email = entregadorEmail.trim();
        if (email.isEmpty) {
          throw const ApiException(
            'Não foi possível identificar o entregador selecionado.',
          );
        }
        caminho += '/entregador/${Uri.encodeComponent(email)}';
      }

      final response = await http
          .get(Uri.parse(caminho), headers: headers)
          .timeout(_tempoLimite);

      if (response.statusCode != 200) {
        throw _erroResposta(response);
      }

      final entregas = _validarEntregas(response);
      if (await EmpresaService.empresaLogada() != empresaEmail ||
          (await EmpresaService.headersAutenticados())['Authorization'] !=
              headers['Authorization']) {
        throw _sessaoExpirada;
      }
      return entregas;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'O servidor demorou para responder. Atualize as entregas e tente novamente.',
      );
    } catch (e) {
      throw ApiException(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível carregar as entregas. Tente novamente.',
        ),
      );
    }
  }

  static Future<List<dynamic>> buscarEntregas() {
    return _buscarEntregas();
  }

  static Future<List<dynamic>> buscarEntregasDoEntregador(
    String entregadorEmail,
  ) {
    return _buscarEntregas(entregadorEmail: entregadorEmail);
  }

  static bool _tratarFalha(
    Object erro, {
    required bool lancarErro,
    required String mensagemPadrao,
  }) {
    if (!lancarErro) return false;
    if (erro is ApiException) throw erro;
    throw ApiException(
      ApiService.mensagemErro(erro, mensagemPadrao: mensagemPadrao),
    );
  }

  static Future<bool> editarEntrega({
    required int id,
    required String cliente,
    required String endereco,
    required double valor,
    required String observacao,
    bool lancarErro = false,
  }) async {
    try {
      await _empresaAutenticada();
      final headers = await _headersAutenticados();
      if (id <= 0) {
        throw const ApiException('Não foi possível identificar a entrega.');
      }
      if (!valor.isFinite) {
        throw const ApiException('Informe um valor válido para a entrega.');
      }

      final response = await http
          .put(
            Uri.parse('${ApiConfig.entregas}/$id'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'cliente': cliente,
              'endereco': endereco,
              'valor': valor,
              'observacao': observacao,
            }),
          )
          .timeout(_tempoLimite);

      if (response.statusCode != 200) {
        throw _erroResposta(response);
      }
      return true;
    } catch (e) {
      return _tratarFalha(
        e,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível editar a entrega. Tente novamente.',
      );
    }
  }

  static Future<bool> cancelarEntrega(int id, {bool lancarErro = false}) async {
    try {
      await _empresaAutenticada();
      final headers = await _headersAutenticados();
      if (id <= 0) {
        throw const ApiException('Não foi possível identificar a entrega.');
      }

      final response = await http
          .delete(Uri.parse('${ApiConfig.entregas}/$id'), headers: headers)
          .timeout(_tempoLimite);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw _erroResposta(response);
      }
      return true;
    } catch (e) {
      return _tratarFalha(
        e,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível cancelar a entrega. Tente novamente.',
      );
    }
  }
}
