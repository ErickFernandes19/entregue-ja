import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'empresa_service.dart';

class EntregaQrException extends ApiException {
  const EntregaQrException(super.mensagem, {super.statusCode});
}

class EntregaService {
  static const Duration _tempoLimite = Duration(seconds: 20);
  static const Duration _tempoLimiteUpload = Duration(seconds: 60);

  static Future<Map<String, String>> _headersAutenticados({
    bool empresa = false,
  }) async {
    final headers = empresa
        ? await EmpresaService.headersAutenticados()
        : await AuthService.headersAutenticados();
    if ((headers['Authorization'] ?? '').trim().isEmpty) {
      throw const ApiException(
        'Sua sessão expirou. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
    return headers;
  }

  static ApiException _converterErro(Object erro, String mensagemPadrao) {
    if (erro is ApiException) return erro;
    return ApiException(
      ApiService.mensagemErro(erro, mensagemPadrao: mensagemPadrao),
    );
  }

  static T? _tratarFalha<T>(
    Object erro, {
    required bool lancarErro,
    required String mensagemPadrao,
  }) {
    debugPrint('$mensagemPadrao (${erro.runtimeType})');
    if (lancarErro) throw _converterErro(erro, mensagemPadrao);
    return null;
  }

  static Map<String, dynamic> _decodificarMapa(String corpo) {
    final dados = jsonDecode(corpo);
    if (dados is Map<String, dynamic>) return dados;
    throw const FormatException('Resposta inválida do servidor.');
  }

  static MediaType _tipoImagem(String nomeArquivo) {
    final nome = nomeArquivo.toLowerCase();

    if (nome.endsWith('.png')) {
      return MediaType('image', 'png');
    }

    if (nome.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }

    return MediaType('image', 'jpeg');
  }

  static String urlComprovante({
    required String idEntrega,
    String? referencia,
  }) {
    if (referencia == null || referencia.trim().isEmpty) {
      return '';
    }

    final valor = referencia.trim();

    if (valor.startsWith('http://') || valor.startsWith('https://')) {
      return valor;
    }

    if (valor.startsWith('entregas/')) {
      return ApiConfig.urlArquivo(
        '/entregas/${Uri.encodeComponent(idEntrega)}/comprovante/arquivo',
      );
    }

    return ApiConfig.urlArquivo(valor);
  }

  static Future<Uint8List?> buscarBytesComprovante({
    required String idEntrega,
    required String referencia,
    bool empresa = false,
    bool lancarErro = false,
  }) async {
    try {
      final url = urlComprovante(idEntrega: idEntrega, referencia: referencia);
      if (url.isEmpty) {
        throw const ApiException('Nenhum comprovante está disponível.');
      }
      final headers = await _headersAutenticados(empresa: empresa);
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_tempoLimite);
      if (response.statusCode == 200) {
        if (response.bodyBytes.isEmpty) {
          throw const ApiException('O comprovante está vazio.');
        }
        return response.bodyBytes;
      }
      throw ApiService.erroHttp(
        response.statusCode,
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (e) {
      return _tratarFalha<Uint8List>(
        e,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível carregar o comprovante.',
      );
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
      final corpo = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode == 200) return _decodificarMapa(corpo);
      throw ApiService.erroHttp(response.statusCode, corpo);
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>>(
        e,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível consultar a entrega.',
      );
    }
  }

  static Map<String, dynamic> _respostaQr(http.Response response) {
    final corpo = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      final erro = ApiService.erroHttp(response.statusCode, corpo);
      final padrao = ApiService.erroHttp(response.statusCode, '').mensagem;
      final mensagem = erro.mensagem != padrao
          ? erro.mensagem
          : switch (response.statusCode) {
              400 => 'Esta entrega não está disponível para atribuição.',
              403 => 'Você não tem permissão para acessar esta entrega.',
              404 => 'Entrega não encontrada.',
              409 =>
                'Esta entrega já foi assumida ou não está mais disponível.',
              _ => erro.mensagem,
            };
      throw EntregaQrException(mensagem, statusCode: erro.statusCode);
    }
    return _decodificarMapa(corpo);
  }

  static Future<Map<String, dynamic>> consultarEntregaQr(String id) async {
    if (id.trim().isEmpty) {
      throw const EntregaQrException('O QR Code não contém um ID válido.');
    }

    try {
      final headers = await _headersAutenticados();
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.entregas}/${Uri.encodeComponent(id.trim())}/consultar-qr',
            ),
            headers: headers,
          )
          .timeout(_tempoLimite);
      return _respostaQr(response);
    } on EntregaQrException {
      rethrow;
    } catch (e) {
      final erro = _converterErro(
        e,
        'Não foi possível consultar o QR Code. Tente novamente.',
      );
      throw EntregaQrException(erro.mensagem, statusCode: erro.statusCode);
    }
  }

  static Future<Map<String, dynamic>> assumirEntregaQr(String id) async {
    if (id.trim().isEmpty) {
      throw const EntregaQrException('O QR Code não contém um ID válido.');
    }

    try {
      final headers = await _headersAutenticados();
      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.entregas}/${Uri.encodeComponent(id.trim())}/assumir-qr',
            ),
            headers: headers,
          )
          .timeout(_tempoLimite);
      return _respostaQr(response);
    } on EntregaQrException {
      rethrow;
    } catch (e) {
      final erro = _converterErro(
        e,
        'Não foi possível assumir a entrega. Tente novamente.',
      );
      throw EntregaQrException(erro.mensagem, statusCode: erro.statusCode);
    }
  }

  static Future<Map<String, dynamic>?> concluirEntrega({
    required String idEntrega,
    required Uint8List fotoBytes,
    required String nomeArquivo,
    required double latitude,
    required double longitude,
    String? observacao,
    bool lancarErro = false,
  }) async {
    try {
      if (fotoBytes.isEmpty) {
        throw const ApiException('Tire uma foto para comprovar a entrega.');
      }

      final headers = await _headersAutenticados();

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
          '${ApiConfig.entregas}/'
          '${Uri.encodeComponent(idEntrega)}/concluir',
        ),
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

      if (observacao != null && observacao.trim().isNotEmpty) {
        request.fields['observacao'] = observacao.trim();
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'foto',
          fotoBytes,
          filename: nomeArquivo,
          contentType: _tipoImagem(nomeArquivo),
        ),
      );

      final response = await request.send().timeout(_tempoLimiteUpload);
      final bytes = await response.stream.toBytes().timeout(_tempoLimiteUpload);
      final corpo = utf8.decode(bytes, allowMalformed: true);

      if (response.statusCode == 200) {
        return _decodificarMapa(corpo);
      }
      throw ApiService.erroHttp(response.statusCode, corpo);
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>>(
        e,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível concluir a entrega.',
      );
    }
  }

  static Future<Map<String, dynamic>?> registrarNaoEntrega({
    required String idEntrega,
    required Uint8List fotoBytes,
    required String nomeArquivo,
    required String motivo,
    required String justificativa,
    required double latitude,
    required double longitude,
    bool lancarErro = false,
  }) async {
    try {
      if (fotoBytes.isEmpty ||
          motivo.trim().isEmpty ||
          justificativa.trim().isEmpty) {
        throw const ApiException(
          'Informe o motivo, a justificativa e tire uma foto da tentativa.',
        );
      }

      final headers = await _headersAutenticados();

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
          '${ApiConfig.entregas}/'
          '${Uri.encodeComponent(idEntrega)}/nao-entregue',
        ),
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
        http.MultipartFile.fromBytes(
          'foto',
          fotoBytes,
          filename: nomeArquivo,
          contentType: _tipoImagem(nomeArquivo),
        ),
      );

      final response = await request.send().timeout(_tempoLimiteUpload);
      final bytes = await response.stream.toBytes().timeout(_tempoLimiteUpload);
      final corpo = utf8.decode(bytes, allowMalformed: true);

      if (response.statusCode == 200) {
        return _decodificarMapa(corpo);
      }
      throw ApiService.erroHttp(response.statusCode, corpo);
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>>(
        e,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível registrar a tentativa de entrega.',
      );
    }
  }
}
