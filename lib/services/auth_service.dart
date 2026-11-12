import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class AuthService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static StreamSubscription<String>? _tokenSubscription;
  static Future<void> _filaFcm = Future<void>.value();
  static bool _encerrandoSessao = false;

  static Future<void> _enfileirarFcm(Future<void> Function() operacao) {
    final proxima = _filaFcm.then((_) => operacao());
    _filaFcm = proxima.catchError((Object erro) {
      debugPrint('Erro na operação FCM do entregador: $erro');
    });
    return _filaFcm;
  }

  static bool get _firebaseDisponivel =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      Firebase.apps.isNotEmpty;

  static Uri get _urlDispositivos {
    final authUri = Uri.parse(ApiConfig.auth);
    final segmentos = authUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segmentos.isNotEmpty && segmentos.last == 'auth') {
      segmentos.removeLast();
    }
    return authUri.replace(
      pathSegments: [...segmentos, 'notificacoes', 'dispositivos'],
      query: null,
      fragment: null,
    );
  }

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

  static Future<void> registrarDispositivoFcm() =>
      _enfileirarFcm(_registrarDispositivoFcm);

  static Future<void> _registrarDispositivoFcm() async {
    if (!_firebaseDisponivel || _encerrandoSessao) return;

    try {
      final jwt = await obterToken();
      if (jwt == null || jwt.isEmpty) return;

      final tokenFcm = await FirebaseMessaging.instance.getToken();
      if (tokenFcm == null || tokenFcm.isEmpty) return;
      if (_encerrandoSessao || await obterToken() != jwt) return;

      final response = await http
          .post(
            _urlDispositivos,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwt',
            },
            body: jsonEncode({'token': tokenFcm, 'plataforma': 'ANDROID'}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 204 && response.statusCode != 200) {
        debugPrint(
          'Falha ao registrar dispositivo FCM: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Erro ao registrar dispositivo FCM: $e');
    }
  }

  static Future<void> inicializarRegistroFcm() async {
    if (!_firebaseDisponivel) return;

    _tokenSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => unawaited(registrarDispositivoFcm()),
      onError: (Object erro) => debugPrint('Erro ao renovar token FCM: $erro'),
    );

    await registrarDispositivoFcm();
  }

  static Future<void> _removerDispositivoFcm() async {
    if (!_firebaseDisponivel) return;

    try {
      final jwt = await obterToken();
      if (jwt == null || jwt.isEmpty) return;

      final tokenFcm = await FirebaseMessaging.instance.getToken();
      if (tokenFcm == null || tokenFcm.isEmpty) return;

      final request = http.Request('DELETE', _urlDispositivos)
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        })
        ..body = jsonEncode({'token': tokenFcm, 'plataforma': 'ANDROID'});

      final client = http.Client();
      try {
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 204 && response.statusCode != 404) {
          debugPrint(
            'Falha ao remover dispositivo FCM: ${response.statusCode}',
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Erro ao remover dispositivo FCM: $e');
    }
  }

  static Future<Map<String, dynamic>?> login(String email, String senha) async {
    try {
      debugPrint('Tentando login...');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.auth}/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'senha': senha}),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));

        final token = data['token']?.toString();

        if (token == null || token.isEmpty) {
          debugPrint('Login sem token JWT retornado pelo backend.');
          return null;
        }

        await _secureStorage.write(key: 'jwt_token', value: token);
        _encerrandoSessao = false;
        unawaited(inicializarRegistroFcm());

        debugPrint('Login realizado e token armazenado.');

        return data;
      }

      return null;
    } catch (e) {
      debugPrint('Erro login: $e');
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
      debugPrint('Erro ao buscar vínculo pendente: $e');
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
      debugPrint('Erro ao buscar perfil: $e');
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

      debugPrint('Erro foto status: ${response.statusCode}');

      return null;
    } catch (e) {
      debugPrint('Erro ao enviar foto: $e');
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
      debugPrint('Erro ao aceitar vínculo: $e');
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
      debugPrint('Erro ao recusar vínculo: $e');
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
      debugPrint('Erro ao buscar empresa vinculada: $e');
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
      debugPrint('Erro ao atualizar configurações do veículo: $e');
      return false;
    }
  }

  static Future<bool> cadastrar(String nome, String email, String senha) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.auth}/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'nome': nome, 'email': email, 'senha': senha}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('Cadastro status: ${response.statusCode}');

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Erro cadastro: $e');
      return false;
    }
  }

  static Future<bool> confirmarCadastro(String email, String codigo) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.auth}/confirmar-cadastro'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'codigo': codigo.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('Confirmação de cadastro status: ${response.statusCode}');

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Erro ao confirmar cadastro: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> _requisicaoRecuperacao(
    String metodo,
    String endpoint,
    Map<String, String> dados,
  ) async {
    try {
      final uri = Uri.parse('${ApiConfig.auth}/$endpoint');
      final headers = {'Content-Type': 'application/json'};
      final corpo = jsonEncode(dados);

      final http.Response response;
      if (metodo == 'PUT') {
        response = await http
            .put(uri, headers: headers, body: corpo)
            .timeout(const Duration(seconds: 15));
      } else {
        response = await http
            .post(uri, headers: headers, body: corpo)
            .timeout(const Duration(seconds: 15));
      }

      String mensagem = response.statusCode == 200
          ? 'Operação realizada com sucesso'
          : 'Não foi possível concluir a solicitação';

      try {
        final resposta = jsonDecode(response.body);
        if (resposta is Map && resposta['mensagem'] is String) {
          mensagem = resposta['mensagem'] as String;
        }
      } catch (_) {}

      return {
        'sucesso': response.statusCode >= 200 && response.statusCode < 300,
        'mensagem': mensagem,
      };
    } catch (e) {
      debugPrint('Erro na recuperação de senha: $e');
      return {
        'sucesso': false,
        'mensagem': 'Não foi possível conectar ao servidor. Tente novamente.',
      };
    }
  }

  static Future<Map<String, dynamic>> solicitarCodigoRecuperacao(String email) {
    return _requisicaoRecuperacao('POST', 'esqueci-senha', {
      'email': email.trim(),
    });
  }

  static Future<Map<String, dynamic>> verificarCodigoRecuperacao(
    String email,
    String codigo,
  ) {
    return _requisicaoRecuperacao('POST', 'verificar-codigo', {
      'email': email.trim(),
      'codigo': codigo.trim(),
    });
  }

  static Future<Map<String, dynamic>> redefinirSenha(
    String email,
    String codigo,
    String novaSenha,
  ) {
    return _requisicaoRecuperacao('PUT', 'redefinir-senha', {
      'email': email.trim(),
      'codigo': codigo.trim(),
      'novaSenha': novaSenha,
    });
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

      debugPrint('Atualizar perfil status: ${response.statusCode}');

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
      debugPrint('Erro ao atualizar perfil: $e');
      return null;
    }
  }

  static Future<void> salvarUsuario(String email, String nome) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('usuario_logado', email);
    await prefs.setString('usuario_nome', nome);
    unawaited(inicializarRegistroFcm());
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
    _encerrandoSessao = true;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    await _filaFcm;
    await _removerDispositivoFcm();
    await _secureStorage.delete(key: 'jwt_token');

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('usuario_logado');
    await prefs.remove('usuario_nome');
    await prefs.remove('usuario_foto');
  }
}
