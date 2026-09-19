import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class EmpresaService {
  static Future<Map<String, dynamic>?> login(String email, String senha) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.empresas}/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'senha': senha}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return null;
    } catch (e) {
      print('Erro login empresa: $e');
      return null;
    }
  }

  static Future<void> salvarDadosEmpresa({
    required String email,
    required String nome,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('empresa_logada', email);
    await prefs.setString('empresa_nome', nome);
  }

  static Future<String?> nomeEmpresa() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('empresa_nome');
  }

  static Future<void> salvarEmpresa(String email) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('empresa_logada', email);
  }

  static Future<String?> empresaLogada() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('empresa_logada');
  }

  static Future<void> logoutEmpresa() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('empresa_logada');
    await prefs.remove('empresa_nome');
    await prefs.remove('empresa_foto');
  }

  static Future<bool> vincularEntregador(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) {
        return false;
      }

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/$empresaEmail/'
          'entregadores/$entregadorEmail/solicitar',
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao solicitar vínculo: $e');
      return false;
    }
  }

  static Future<List<dynamic>> buscarEntregadoresPendentes() async {
    try {
      final email = await empresaLogada();

      if (email == null) {
        return [];
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.empresas}/$email/entregadores-pendentes'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return [];
    } catch (e) {
      print('Erro ao buscar vínculos pendentes: $e');
      return [];
    }
  }

  static Future<List<dynamic>> buscarEntregadores() async {
    try {
      final email = await empresaLogada();

      if (email == null) {
        return [];
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.empresas}/$email/entregadores'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return [];
    } catch (e) {
      print('Erro ao buscar entregadores: $e');
      return [];
    }
  }

  static Future<bool> cancelarSolicitacaoVinculo(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) {
        return false;
      }

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/$empresaEmail/'
          'entregadores/$entregadorEmail/cancelar-solicitacao',
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao cancelar solicitação de vínculo: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> atualizarPerfilEmpresa({
    required String nome,
    required String email,
  }) async {
    try {
      final emailAtual = await empresaLogada();

      if (emailAtual == null || emailAtual.isEmpty) {
        return null;
      }

      final emailAtualUrl = Uri.encodeComponent(emailAtual);

      final response = await http.put(
        Uri.parse('${ApiConfig.empresas}/$emailAtualUrl/perfil'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nome': nome, 'email': email}),
      );

      print('Atualizar perfil empresa status: ${response.statusCode}');
      print('Atualizar perfil empresa body: ${response.body}');

      if (response.statusCode != 200) {
        return null;
      }

      final data = Map<String, dynamic>.from(jsonDecode(response.body));

      final novoNome = data['nome']?.toString();
      final novoEmail = data['email']?.toString();

      if (novoNome == null || novoEmail == null) {
        return null;
      }

      await salvarDadosEmpresa(email: novoEmail, nome: novoNome);

      return data;
    } catch (e) {
      print('Erro ao atualizar perfil da empresa: $e');
      return null;
    }
  }

  static Future<int> totalEntregadores() async {
    try {
      final email = await empresaLogada();

      if (email == null) {
        return 0;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.empresas}/$email/entregadores/total'),
      );

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        return dados['total'] ?? 0;
      }

      return 0;
    } catch (e) {
      print('Erro ao buscar total de entregadores: $e');
      return 0;
    }
  }

  static Future<bool> desvincularEntregador(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) {
        return false;
      }

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/$empresaEmail/'
          'desvincular/$entregadorEmail',
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao desvincular: $e');
      return false;
    }
  }

  static Future<String?> atualizarFotoEmpresa(String caminhoArquivo) async {
    try {
      final email = await empresaLogada();

      if (email == null) {
        return null;
      }

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.empresas}/$email/foto'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('foto', caminhoArquivo),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          return null;
        }

        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('empresa_foto', foto);

        return foto;
      }

      print('Erro foto empresa status: ${response.statusCode}');
      print('Erro foto empresa body: $body');

      return null;
    } catch (e) {
      print('Erro ao enviar foto da empresa: $e');
      return null;
    }
  }

  static Future<String?> fotoEmpresa() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('empresa_foto');
  }

  static Future<bool> cadastrar(String nome, String email, String senha) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.empresas}/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nome': nome, 'email': email, 'senha': senha}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro cadastro empresa: $e');
      return false;
    }
  }
}
