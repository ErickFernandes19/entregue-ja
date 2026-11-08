import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import 'auth_service.dart';
import 'empresa_service.dart';

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
