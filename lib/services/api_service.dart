import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import 'auth_service.dart';
import 'empresa_service.dart';

class ApiException implements Exception {
  final String mensagem;
  final int? statusCode;

  const ApiException(this.mensagem, {this.statusCode});

  @override
  String toString() => mensagem;
}

class ApiService {
  static const Duration _tempoLimite = Duration(seconds: 20);
  static const Duration _tempoLimiteUpload = Duration(seconds: 60);

  static Future<Map<String, String>> _headersAutenticados() async {
    final headers = await AuthService.headersAutenticados();
    if ((headers['Authorization'] ?? '').trim().isEmpty) {
      throw const ApiException(
        'Sua sessão expirou. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
    return headers;
  }

  static void _registrarErro(String operacao, int statusCode) {
    debugPrint('$operacao: HTTP $statusCode');
  }

  static String? _mensagemServidor(String body) {
    try {
      final dados = jsonDecode(body);
      if (dados is! Map) return null;
      final valor = dados['mensagem'];
      if (valor is! String) return null;
      final mensagem = valor.trim();
      if (mensagem.isEmpty || mensagem.length > 300) return null;
      final tecnico = RegExp(
        r'exception|stacktrace|stack trace|java\.|org\.|sql|jdbc|hibernate|https?://|endpoint|/entregas/|<[^>]*>|[\x00-\x1F\x7F]',
        caseSensitive: false,
      );
      if (tecnico.hasMatch(mensagem)) return null;
      return mensagem;
    } on FormatException {
      return null;
    }
  }

  static ApiException erroHttp(int statusCode, String body) {
    String mensagem;
    if (statusCode == 401) {
      mensagem = 'Sua sessão expirou. Entre novamente na sua conta.';
    } else if (statusCode >= 500) {
      mensagem = 'Ocorreu um problema no servidor. Tente novamente mais tarde.';
    } else {
      final mensagemServidor = statusCode >= 400 && statusCode < 500
          ? _mensagemServidor(body)
          : null;
      mensagem =
          mensagemServidor ??
          (switch (statusCode) {
            400 || 422 => 'Confira os dados informados e tente novamente.',
            403 => 'Você não possui permissão para realizar esta operação.',
            404 => 'O registro solicitado não foi encontrado.',
            408 => 'O servidor demorou para responder. Tente novamente.',
            409 =>
              'Não foi possível realizar a operação no estado atual. Atualize os dados e tente novamente.',
            413 => 'O arquivo enviado é muito grande.',
            415 => 'O formato do arquivo enviado não é aceito.',
            429 =>
              'Muitas solicitações foram realizadas. Aguarde um momento e tente novamente.',
            _ => 'Não foi possível realizar a operação. Tente novamente.',
          });
    }
    return ApiException(mensagem, statusCode: statusCode);
  }

  static ApiException _converterErro(Object erro, String mensagemPadrao) {
    if (erro is ApiException) return erro;
    if (erro is TimeoutException) {
      return const ApiException(
        'O servidor demorou para responder. Verifique o resultado da operação antes de tentar novamente.',
      );
    }
    if (erro is http.ClientException) {
      return const ApiException(
        'Não foi possível conectar ao servidor. Verifique sua conexão com a internet e tente novamente.',
      );
    }
    if (erro is FormatException) {
      return const ApiException(
        'O servidor retornou uma resposta inesperada. Tente novamente mais tarde.',
      );
    }
    return ApiException(mensagemPadrao);
  }

  static String mensagemErro(
    Object erro, {
    String mensagemPadrao =
        'Não foi possível realizar a operação. Tente novamente.',
  }) {
    return _converterErro(erro, mensagemPadrao).mensagem;
  }

  static MediaType _tipoImagem(String caminhoFoto) {
    final caminho = caminhoFoto.toLowerCase();
    if (caminho.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (caminho.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }
    return MediaType('image', 'jpeg');
  }

  static Future<Map<String, dynamic>> cadastrarEntregaEntregador({
    required String cliente,
    required String endereco,
    double? valor,
    String? complemento,
    String? observacao,
    double? latitude,
    double? longitude,
  }) async {
    if (cliente.trim().isEmpty || endereco.trim().isEmpty) {
      throw const ApiException('Informe o cliente e o endereço da entrega.');
    }
    try {
      final headers = await _headersAutenticados();
      final response = await http
          .post(
            Uri.parse('${ApiConfig.entregas}/entregador'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'cliente': cliente.trim(),
              'endereco': endereco.trim(),
              'valor': valor,
              'complemento': complemento,
              'observacao': observacao,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(_tempoLimite);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final dados = jsonDecode(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        );
        if (dados is Map<String, dynamic> && dados['id'] != null) {
          return dados;
        }
        throw const FormatException(
          'O servidor não retornou uma entrega salva com ID.',
        );
      }
      _registrarErro(
        'Erro ao cadastrar entrega do entregador',
        response.statusCode,
      );
      throw erroHttp(
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (e) {
      debugPrint('Falha ao cadastrar entrega: ${e.runtimeType}');
      throw _converterErro(e, 'Não foi possível cadastrar a entrega.');
    }
  }

  static Future<Map<String, dynamic>?> buscarEntrega(
    String id, {
    bool lancarErro = false,
  }) async {
    try {
      final headers = await _headersAutenticados();
      final response = await http
          .get(
            Uri.parse('${ApiConfig.entregas}/${Uri.encodeComponent(id)}'),
            headers: headers,
          )
          .timeout(_tempoLimite);
      if (response.statusCode == 200) {
        final dados = jsonDecode(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        );
        if (dados is Map) {
          return Map<String, dynamic>.from(dados);
        }
        throw const FormatException('Resposta inválida do servidor.');
      }
      _registrarErro('Erro ao buscar entrega', response.statusCode);
      throw erroHttp(
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (e) {
      debugPrint('buscarEntrega: ${e.runtimeType}');
      if (lancarErro) {
        throw _converterErro(e, 'Não foi possível consultar a entrega.');
      }
      return null;
    }
  }

  static Future<List<dynamic>> buscarEntregasDoEntregador(String email) async {
    try {
      final headers = await _headersAutenticados();
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.entregas}/entregador/${Uri.encodeComponent(email)}',
            ),
            headers: headers,
          )
          .timeout(_tempoLimite);
      if (response.statusCode == 200) {
        final dados = jsonDecode(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        );
        if (dados is List) return dados;
        throw const FormatException(
          'O servidor não retornou uma lista de entregas.',
        );
      }
      _registrarErro(
        'Erro ao buscar entregas do entregador',
        response.statusCode,
      );
      throw erroHttp(
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (e) {
      debugPrint('Erro ao buscar entregas do entregador: ${e.runtimeType}');
      throw _converterErro(e, 'Não foi possível carregar suas entregas.');
    }
  }

  static Future<bool> excluirEntrega(int id, {bool lancarErro = false}) async {
    try {
      final headers = await _headersAutenticados();
      final response = await http
          .delete(Uri.parse('${ApiConfig.entregas}/$id'), headers: headers)
          .timeout(_tempoLimite);
      if (response.statusCode == 200 || response.statusCode == 204) return true;
      _registrarErro('Erro ao excluir entrega', response.statusCode);
      throw erroHttp(
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (e) {
      debugPrint('excluirEntrega: ${e.runtimeType}');
      if (lancarErro) {
        throw _converterErro(e, 'Não foi possível remover a entrega.');
      }
      return false;
    }
  }

  static Future<bool> marcarEntregaEmRota(
    int id, {
    bool lancarErro = false,
  }) async {
    try {
      final headers = await _headersAutenticados();
      final response = await http
          .put(Uri.parse('${ApiConfig.entregas}/$id/em-rota'), headers: headers)
          .timeout(_tempoLimite);
      if (response.statusCode == 200) return true;
      _registrarErro('Erro ao marcar entrega em rota', response.statusCode);
      throw erroHttp(
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (e) {
      debugPrint('marcarEntregaEmRota: ${e.runtimeType}');
      if (lancarErro) {
        throw _converterErro(e, 'Não foi possível iniciar a rota da entrega.');
      }
      return false;
    }
  }

  static Future<bool> atualizarStatusEntrega(int id) async {
    debugPrint(
      'A alteração de status da entrega #$id deve utilizar o fluxo '
      'de finalização com fotografia e localização GPS.',
    );
    return false;
  }

  static Future<bool> enviarLocalizacaoEntregador({
    required int id,
    required double latitude,
    required double longitude,
  }) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return false;
    }
    try {
      final headers = await _headersAutenticados();
      final response = await http
          .put(
            Uri.parse('${ApiConfig.entregas}/$id/localizacao'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return true;
      _registrarErro(
        'Erro ao enviar localização da entrega #$id',
        response.statusCode,
      );
      return false;
    } catch (e) {
      debugPrint(
        'Erro ao enviar localização da entrega #$id: ${e.runtimeType}',
      );
      return false;
    }
  }

  static Future<Map<String, dynamic>?> buscarLocalizacaoEntregador(
    int id,
  ) async {
    try {
      final headers = await EmpresaService.headersAutenticados();
      final response = await http
          .get(
            Uri.parse('${ApiConfig.entregas}/$id/localizacao'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final dados = jsonDecode(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        );
        if (dados is Map<String, dynamic>) return dados;
        return null;
      }
      if (response.statusCode == 204 || response.statusCode == 404) return null;
      _registrarErro(
        'Erro ao consultar localização da entrega #$id',
        response.statusCode,
      );
      return null;
    } catch (e) {
      debugPrint(
        'Erro ao consultar localização da entrega #$id: ${e.runtimeType}',
      );
      return null;
    }
  }

  static Future<Map<String, dynamic>?> concluirEntrega({
    required int id,
    required String caminhoFoto,
    required double latitude,
    required double longitude,
    String observacao = '',
    bool lancarErro = false,
  }) async {
    try {
      final headers = await _headersAutenticados();
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.entregas}/$id/concluir'),
      );
      final autorizacao = headers['Authorization'];
      if (autorizacao == null || autorizacao.isEmpty) {
        throw const ApiException(
          'Sua sessão expirou. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }
      request.headers['Authorization'] = autorizacao;
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      if (observacao.trim().isNotEmpty) {
        request.fields['observacao'] = observacao.trim();
      }
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          caminhoFoto,
          contentType: _tipoImagem(caminhoFoto),
        ),
      );
      debugPrint('Enviando comprovante da entrega #$id...');
      final streamedResponse = await request.send().timeout(_tempoLimiteUpload);
      final body = await streamedResponse.stream
          .bytesToString(utf8)
          .timeout(_tempoLimiteUpload);
      if (streamedResponse.statusCode == 200) {
        if (body.isEmpty) return {'sucesso': true, 'status': 'ENTREGUE'};
        final dados = jsonDecode(body);
        if (dados is Map) {
          return Map<String, dynamic>.from(dados);
        }
        throw const FormatException('Resposta inválida do servidor.');
      }
      _registrarErro('Erro ao concluir entrega', streamedResponse.statusCode);
      throw erroHttp(streamedResponse.statusCode, body);
    } catch (e) {
      debugPrint('concluirEntrega: ${e.runtimeType}');
      if (lancarErro) {
        throw _converterErro(
          e,
          'Não foi possível enviar o comprovante da entrega. Confira a foto e tente novamente.',
        );
      }
      return null;
    }
  }

  static Future<Map<String, dynamic>?> registrarNaoEntrega({
    required int id,
    required String caminhoFoto,
    required String motivo,
    required String justificativa,
    required double latitude,
    required double longitude,
    bool lancarErro = false,
  }) async {
    try {
      if (motivo.trim().isEmpty) {
        throw const ApiException('Informe o motivo da não entrega.');
      }
      if (justificativa.trim().isEmpty) {
        throw const ApiException('Informe a justificativa da não entrega.');
      }
      final headers = await _headersAutenticados();
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.entregas}/$id/nao-entregue'),
      );
      final autorizacao = headers['Authorization'];
      if (autorizacao == null || autorizacao.isEmpty) {
        throw const ApiException(
          'Sua sessão expirou. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }
      request.headers['Authorization'] = autorizacao;
      request.fields['motivo'] = motivo.trim();
      request.fields['justificativa'] = justificativa.trim();
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      request.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          caminhoFoto,
          contentType: _tipoImagem(caminhoFoto),
        ),
      );
      debugPrint('Registrando tentativa da entrega #$id...');
      final streamedResponse = await request.send().timeout(_tempoLimiteUpload);
      final body = await streamedResponse.stream
          .bytesToString(utf8)
          .timeout(_tempoLimiteUpload);
      if (streamedResponse.statusCode == 200) {
        if (body.isEmpty) return {'sucesso': true, 'status': 'NAO_ENTREGUE'};
        final dados = jsonDecode(body);
        if (dados is Map) {
          return Map<String, dynamic>.from(dados);
        }
        throw const FormatException('Resposta inválida do servidor.');
      }
      _registrarErro(
        'Erro ao registrar não entrega',
        streamedResponse.statusCode,
      );
      throw erroHttp(streamedResponse.statusCode, body);
    } catch (e) {
      debugPrint('registrarNaoEntrega: ${e.runtimeType}');
      if (lancarErro) {
        throw _converterErro(
          e,
          'Não foi possível registrar a tentativa de entrega. Confira a foto e tente novamente.',
        );
      }
      return null;
    }
  }
}
