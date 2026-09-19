import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiService {
  static Future<Map<String, dynamic>?> buscarEntrega(String id) async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.entregas}/$id'));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      print('Erro buscar entrega: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return null;
    } catch (e) {
      print('Erro API: $e');
      return null;
    }
  }

  static Future<List<dynamic>> buscarEntregasDoEntregador(String email) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.entregas}/entregador/${Uri.encodeComponent(email)}',
        ),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      print('Erro ao buscar entregas do entregador: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return [];
    } catch (e) {
      print('Erro ao buscar entregas do entregador: $e');
      return [];
    }
  }

  static Future<bool> marcarEntregaEmRota(int id) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.entregas}/$id/em-rota'),
      );

      if (response.statusCode == 200) {
        return true;
      }

      print('Erro ao marcar entrega em rota: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return false;
    } catch (e) {
      print('Erro ao marcar entrega em rota: $e');
      return false;
    }
  }

  static Future<bool> atualizarStatusEntrega(int id) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.entregas}/$id/status'),
      );

      if (response.statusCode == 200) {
        return true;
      }

      print('Erro ao atualizar status: ${response.statusCode}');
      print('Resposta: ${response.body}');

      return false;
    } catch (e) {
      print('Erro status: $e');
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
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.entregas}/$id/concluir'),
      );

      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();

      if (observacao.trim().isNotEmpty) {
        request.fields['observacao'] = observacao.trim();
      }

      request.files.add(await http.MultipartFile.fromPath('foto', caminhoFoto));

      print('Enviando comprovante da entrega #$id...');

      final streamedResponse = await request.send();

      final body = await streamedResponse.stream.bytesToString();

      print(
        'Concluir entrega status: '
        '${streamedResponse.statusCode}',
      );

      print('Concluir entrega body: $body');

      if (streamedResponse.statusCode == 200) {
        if (body.isEmpty) {
          return {'sucesso': true, 'status': 'ENTREGUE'};
        }

        return jsonDecode(body);
      }

      return null;
    } catch (e) {
      print('Erro ao concluir entrega: $e');

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
        print('Não entrega não enviada: motivo vazio');

        return null;
      }

      if (justificativa.trim().isEmpty) {
        print('Não entrega não enviada: justificativa vazia');

        return null;
      }

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.entregas}/$id/nao-entregue'),
      );

      request.fields['motivo'] = motivo.trim();

      request.fields['justificativa'] = justificativa.trim();

      request.fields['latitude'] = latitude.toString();

      request.fields['longitude'] = longitude.toString();

      request.files.add(await http.MultipartFile.fromPath('foto', caminhoFoto));

      print('Registrando tentativa da entrega #$id...');

      final streamedResponse = await request.send();

      final body = await streamedResponse.stream.bytesToString();

      print(
        'Não entrega status: '
        '${streamedResponse.statusCode}',
      );

      print('Não entrega body: $body');

      if (streamedResponse.statusCode == 200) {
        if (body.isEmpty) {
          return {'sucesso': true, 'status': 'NAO_ENTREGUE'};
        }

        return jsonDecode(body);
      }

      return null;
    } catch (e) {
      print('Erro ao registrar não entrega: $e');

      return null;
    }
  }
}
