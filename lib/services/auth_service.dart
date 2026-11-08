import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class AuthService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static Future<String?> obterToken() async {
    return _secureStorage.read(key: 'jwt_token');
  }

  static Future<Map<String, String>> headersAutenticados() async {
    final token = await obterToken();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>?> login(String email, String senha) async {
    try {
      print('Tentando login...');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.auth}/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'senha': senha}),
          )
          .timeout(const Duration(seconds: 10));

      print('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));

        final token = data['token']?.toString();

        if (token == null || token.isEmpty) {
          print('Login sem token JWT retornado pelo backend.');
          return null;
        }

        await _secureStorage.write(key: 'jwt_token', value: token);

        print('Login realizado e token armazenado.');

        return data;
      }

      return null;
    } catch (e) {
      print('Erro login: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> buscarVinculoPendente() async {
    try {
      final email = await usuarioLogado();

      if (email == null) return null;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.auth}/${Uri.encodeComponent(email)}/vinculo-pendente',
        ),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      return null;
    } catch (e) {
      print('Erro ao buscar vínculo pendente: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> buscarPerfil() async {
    try {
      final email = await usuarioLogado();

      if (email == null) return null;

      final response = await http.get(
        Uri.parse('${ApiConfig.auth}/${Uri.encodeComponent(email)}/perfil'),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      return null;
    } catch (e) {
      print('Erro ao buscar perfil: $e');
      return null;
    }
  }

  static Future<String?> atualizarFotoPerfil(String caminhoArquivo) async {
    try {
      final email = await usuarioLogado();

      if (email == null) return null;

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.auth}/${Uri.encodeComponent(email)}/foto'),
      );

      final token = await obterToken();

      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(
        await http.MultipartFile.fromPath('foto', caminhoArquivo),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(body));

        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          return null;
        }

        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('usuario_foto', foto);

        return foto;
      }

      print('Erro foto status: ${response.statusCode}');

      return null;
    } catch (e) {
      print('Erro ao enviar foto: $e');
      return null;
    }
  }

  static Future<String?> fotoUsuario() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('usuario_foto');
  }

  static Future<bool> aceitarVinculo() async {
    try {
      final email = await usuarioLogado();

      if (email == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.auth}/${Uri.encodeComponent(email)}/aceitar-vinculo',
        ),
        headers: await headersAutenticados(),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao aceitar vínculo: $e');
      return false;
    }
  }

  static Future<bool> recusarVinculo() async {
    try {
      final email = await usuarioLogado();

      if (email == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.auth}/${Uri.encodeComponent(email)}/recusar-vinculo',
        ),
        headers: await headersAutenticados(),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao recusar vínculo: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> buscarEmpresaVinculada() async {
    try {
      final email = await usuarioLogado();

      if (email == null) return null;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.auth}/${Uri.encodeComponent(email)}/empresa-vinculada',
        ),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      return null;
    } catch (e) {
      print('Erro ao buscar empresa vinculada: $e');
      return null;
    }
  }

  static Future<bool> atualizarConfiguracoesVeiculo({
    required String veiculo,
    required String capacidadeCarga,
  }) async {
    try {
      final email = await usuarioLogado();

      if (email == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.auth}/${Uri.encodeComponent(email)}/configuracoes-veiculo',
        ),
        headers: await headersAutenticados(),
        body: jsonEncode({
          'veiculo': veiculo,
          'capacidadeCarga': capacidadeCarga,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Erro ao atualizar configurações do veículo: $e');
      return false;
    }
  }

  static Future<bool> cadastrar(String nome, String email, String senha) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.auth}/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nome': nome, 'email': email, 'senha': senha}),
      );

      print('Cadastro status: ${response.statusCode}');

      return response.statusCode == 200;
    } catch (e) {
      print('Erro cadastro: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> atualizarPerfil({
    required String nome,
    required String email,
  }) async {
    try {
      final emailAtual = await usuarioLogado();

      if (emailAtual == null) return null;

      final emailAtualUrl = Uri.encodeComponent(emailAtual);

      final response = await http.put(
        Uri.parse('${ApiConfig.auth}/$emailAtualUrl/perfil'),
        headers: await headersAutenticados(),
        body: jsonEncode({'nome': nome, 'email': email}),
      );

      print('Atualizar perfil status: ${response.statusCode}');

      if (response.statusCode != 200) {
        return null;
      }

      final data = Map<String, dynamic>.from(jsonDecode(response.body));

      final novoNome = data['nome']?.toString();
      final novoEmail = data['email']?.toString();

      if (novoNome == null || novoEmail == null) {
        return null;
      }

      await salvarUsuario(novoEmail, novoNome);

      return data;
    } catch (e) {
      print('Erro ao atualizar perfil: $e');
      return null;
    }
  }

  static Future<void> salvarUsuario(String email, String nome) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('usuario_logado', email);
    await prefs.setString('usuario_nome', nome);
  }

  static Future<String?> nomeUsuario() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('usuario_nome');
  }

  static Future<String?> usuarioLogado() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('usuario_logado');
  }

  static Future<void> logout() async {
    await _secureStorage.delete(key: 'jwt_token');

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('usuario_logado');
    await prefs.remove('usuario_nome');
    await prefs.remove('usuario_foto');
  }
}
