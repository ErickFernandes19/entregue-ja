import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import 'auth_service.dart';

class ApiService {
  static Future<Map<String, String>> _headersAutenticados() async {
    return await AuthService.headersAutenticados();
  }

  static void _registrarErro(String operacao, int statusCode, String body) {
    debugPrint('$operacao: HTTP $statusCode');

    if (statusCode == 401) {
      debugPrint('Sessão inválida ou token JWT expirado.');
    } else if (statusCode == 403) {
      debugPrint('Acesso negado pelo servidor.');
    } else {
      debugPrint('Resposta: $body');
    }
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
      throw ArgumentError('Informe o cliente e o endereço da entrega.');
    }

    final headers = await _headersAutenticados();
    final response = await http.post(
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
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final dados = jsonDecode(response.body);
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
      response.body,
    );
    throw Exception('Falha ao cadastrar entrega: HTTP ${response.statusCode}');
  }

  static Future<Map<String, dynamic>?> buscarEntrega(String id) async {
    try {
      final headers = await _headersAutenticados();

      final response = await http.get(
        Uri.parse('${ApiConfig.entregas}/${Uri.encodeComponent(id)}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      _registrarErro(
        'Erro ao buscar entrega',
        response.statusCode,
        response.body,
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao buscar entrega: $e');
      return null;
    }
  }

  static Future<List<dynamic>> buscarEntregasDoEntregador(String email) async {
    try {
      final headers = await _headersAutenticados();

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.entregas}/entregador/${Uri.encodeComponent(email)}',
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados is List) {
          return dados;
        }

        throw const FormatException(
          'O servidor não retornou uma lista de entregas.',
        );
      }

      _registrarErro(
        'Erro ao buscar entregas do entregador',
        response.statusCode,
        response.body,
      );

      throw Exception(
        'Falha ao carregar entregas: HTTP ${response.statusCode}',
      );
    } catch (e) {
      debugPrint('Erro ao buscar entregas do entregador: $e');
      rethrow;
    }
  }

  static Future<bool> excluirEntrega(int id) async {
    try {
      final headers = await _headersAutenticados();

      final response = await http.delete(
        Uri.parse('${ApiConfig.entregas}/$id'),
        headers: headers,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }

      _registrarErro(
        'Erro ao excluir entrega',
        response.statusCode,
        response.body,
      );

      return false;
    } catch (e) {
      debugPrint('Erro ao excluir entrega: $e');
      return false;
    }
  }

  static Future<bool> marcarEntregaEmRota(int id) async {
    try {
      final headers = await _headersAutenticados();

      final response = await http.put(
        Uri.parse('${ApiConfig.entregas}/$id/em-rota'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return true;
      }

      _registrarErro(
        'Erro ao marcar entrega em rota',
        response.statusCode,
        response.body,
      );

      return false;
    } catch (e) {
      debugPrint('Erro ao marcar entrega em rota: $e');
      return false;
    }
  }

  static Future<bool> atualizarStatusEntrega(int id) async {
    try {
      final headers = await _headersAutenticados();

      final response = await http.put(
        Uri.parse('${ApiConfig.entregas}/$id/status'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return true;
      }

      _registrarErro(
        'Erro ao atualizar status',
        response.statusCode,
        response.body,
      );

      return false;
    } catch (e) {
      debugPrint('Erro ao atualizar status: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> concluirEntrega({
    required int id,
    required String caminhoFoto,
    required double latitude,
    required double longitude,
    String observacao = '',
  }) async {
    try {
      final headers = await _headersAutenticados();

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.entregas}/$id/concluir'),
      );

      final autorizacao = headers['Authorization'];

      if (autorizacao == null || autorizacao.isEmpty) {
        debugPrint('Não foi possível concluir: token JWT ausente.');
        return null;
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

      final streamedResponse = await request.send();
      final body = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        if (body.isEmpty) {
          return {'sucesso': true, 'status': 'ENTREGUE'};
        }

        return Map<String, dynamic>.from(jsonDecode(body));
      }

      _registrarErro(
        'Erro ao concluir entrega',
        streamedResponse.statusCode,
        body,
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao concluir entrega: $e');
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
  }) async {
    try {
      if (motivo.trim().isEmpty) {
        debugPrint('Não entrega não enviada: motivo vazio');
        return null;
      }

      if (justificativa.trim().isEmpty) {
        debugPrint('Não entrega não enviada: justificativa vazia');
        return null;
      }

      final headers = await _headersAutenticados();

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.entregas}/$id/nao-entregue'),
      );

      final autorizacao = headers['Authorization'];

      if (autorizacao == null || autorizacao.isEmpty) {
        debugPrint('Não foi possível registrar: token JWT ausente.');
        return null;
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

      final streamedResponse = await request.send();
      final body = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        if (body.isEmpty) {
          return {'sucesso': true, 'status': 'NAO_ENTREGUE'};
        }

        return Map<String, dynamic>.from(jsonDecode(body));
      }

      _registrarErro(
        'Erro ao registrar não entrega',
        streamedResponse.statusCode,
        body,
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao registrar não entrega: $e');
      return null;
    }
  }
}
