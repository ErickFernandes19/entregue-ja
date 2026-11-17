import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import 'auth_service.dart';
import 'empresa_service.dart';

class EntregaQrException implements Exception {
  final String mensagem;
  final int? statusCode;

  const EntregaQrException(this.mensagem, {this.statusCode});

  @override
  String toString() => mensagem;
}

class EntregaService {
  static Future<Map<String, String>> _headersAutenticados({
    bool empresa = false,
  }) async {
    if (empresa) {
      return EmpresaService.headersAutenticados();
    }

    return AuthService.headersAutenticados();
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
  }) async {
    try {
      final url = urlComprovante(idEntrega: idEntrega, referencia: referencia);

      if (url.isEmpty) {
        return null;
      }

      final headers = await _headersAutenticados(empresa: empresa);

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      debugPrint(
        'Erro ao buscar comprovante. '
        'Status: ${response.statusCode}',
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao buscar comprovante: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> buscarEntrega(String id) async {
    try {
      final headers = await AuthService.headersAutenticados();

      final response = await http.get(
        Uri.parse('${ApiConfig.entregas}/${Uri.encodeComponent(id)}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados is Map<String, dynamic>) {
          return dados;
        }

        debugPrint('Resposta inesperada ao buscar entrega.');

        return null;
      }

      if (response.statusCode == 401) {
        debugPrint('Erro 401: sessão expirada ou token inválido.');
        return null;
      }

      if (response.statusCode == 403) {
        debugPrint('Erro 403: acesso à entrega não autorizado.');
        return null;
      }

      if (response.statusCode == 404) {
        debugPrint('Erro 404: entrega não encontrada.');
        return null;
      }

      debugPrint(
        'Erro ao buscar entrega. '
        'Status: ${response.statusCode}',
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao buscar entrega: $e');
      return null;
    }
  }

  static String _mensagemErroQr(
    http.Response response, {
    required bool assumir,
  }) {
    final padrao = switch (response.statusCode) {
      400 => 'Esta entrega não está disponível para atribuição.',
      401 => 'Sua sessão expirou. Entre novamente no aplicativo.',
      403 => 'Você não tem permissão para acessar esta entrega.',
      404 => 'Entrega não encontrada.',
      409 => 'Esta entrega já foi assumida ou não está mais disponível.',
      _ =>
        assumir
            ? 'Não foi possível assumir a entrega. Tente novamente.'
            : 'Não foi possível consultar o QR Code. Tente novamente.',
    };

    try {
      final dados = jsonDecode(response.body);
      if (dados is Map && dados['mensagem'] is String) {
        final mensagem = (dados['mensagem'] as String).trim();
        if (mensagem.isNotEmpty) {
          return mensagem;
        }
      }
    } catch (_) {}

    return padrao;
  }

  static Future<Map<String, dynamic>> _respostaQr(
    http.Response response, {
    required bool assumir,
  }) async {
    if (response.statusCode != 200) {
      throw EntregaQrException(
        _mensagemErroQr(response, assumir: assumir),
        statusCode: response.statusCode,
      );
    }

    try {
      final dados = jsonDecode(response.body);
      if (dados is Map<String, dynamic>) {
        return dados;
      }
    } catch (_) {}

    throw const EntregaQrException('O servidor retornou dados inválidos.');
  }

  static Future<Map<String, dynamic>> consultarEntregaQr(String id) async {
    if (id.trim().isEmpty) {
      throw const EntregaQrException('O QR Code não contém um ID válido.');
    }

    try {
      final headers = await AuthService.headersAutenticados();
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.entregas}/${Uri.encodeComponent(id.trim())}/consultar-qr',
        ),
        headers: headers,
      );
      return await _respostaQr(response, assumir: false);
    } on EntregaQrException {
      rethrow;
    } catch (e) {
      debugPrint('Erro ao consultar QR Code: $e');
      throw const EntregaQrException(
        'Falha de conexão ao consultar a entrega.',
      );
    }
  }

  static Future<Map<String, dynamic>> assumirEntregaQr(String id) async {
    if (id.trim().isEmpty) {
      throw const EntregaQrException('O QR Code não contém um ID válido.');
    }

    try {
      final headers = await AuthService.headersAutenticados();
      final response = await http.put(
        Uri.parse(
          '${ApiConfig.entregas}/${Uri.encodeComponent(id.trim())}/assumir-qr',
        ),
        headers: headers,
      );
      return await _respostaQr(response, assumir: true);
    } on EntregaQrException {
      rethrow;
    } catch (e) {
      debugPrint('Erro ao assumir entrega pelo QR Code: $e');
      throw const EntregaQrException('Falha de conexão ao assumir a entrega.');
    }
  }

  static Future<Map<String, dynamic>?> concluirEntrega({
    required String idEntrega,
    required Uint8List fotoBytes,
    required String nomeArquivo,
    required double latitude,
    required double longitude,
    String? observacao,
  }) async {
    try {
      if (fotoBytes.isEmpty) {
        debugPrint('Foto do comprovante está vazia.');
        return null;
      }

      final headers = await AuthService.headersAutenticados();

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
          '${ApiConfig.entregas}/'
          '${Uri.encodeComponent(idEntrega)}/concluir',
        ),
      );

      final autorizacao = headers['Authorization'];

      if (autorizacao == null || autorizacao.isEmpty) {
        debugPrint('Token do entregador não encontrado.');
        return null;
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

      final response = await request.send();
      final corpo = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final dados = jsonDecode(corpo);

        if (dados is Map<String, dynamic>) {
          return dados;
        }

        return null;
      }

      debugPrint(
        'Erro ao concluir entrega. '
        'Status: ${response.statusCode}. '
        'Resposta: $corpo',
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao concluir entrega: $e');
      return null;
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
  }) async {
    try {
      if (fotoBytes.isEmpty ||
          motivo.trim().isEmpty ||
          justificativa.trim().isEmpty) {
        debugPrint('Dados obrigatórios da não entrega ausentes.');
        return null;
      }

      final headers = await AuthService.headersAutenticados();

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
          '${ApiConfig.entregas}/'
          '${Uri.encodeComponent(idEntrega)}/nao-entregue',
        ),
      );

      final autorizacao = headers['Authorization'];

      if (autorizacao == null || autorizacao.isEmpty) {
        debugPrint('Token do entregador não encontrado.');
        return null;
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

      final response = await request.send();
      final corpo = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final dados = jsonDecode(corpo);

        if (dados is Map<String, dynamic>) {
          return dados;
        }

        return null;
      }

      debugPrint(
        'Erro ao registrar não entrega. '
        'Status: ${response.statusCode}. '
        'Resposta: $corpo',
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao registrar não entrega: $e');
      return null;
    }
  }
}
