import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class EmpresaService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static StreamSubscription<String>? _tokenSubscription;
  static Future<void> _filaFcm = Future<void>.value();
  static bool _encerrandoSessao = false;

  static Future<void> _enfileirarFcm(Future<void> Function() operacao) {
    final proxima = _filaFcm.then((_) => operacao());
    _filaFcm = proxima.catchError((Object erro) {
      debugPrint('Erro na operação FCM da empresa: $erro');
    });
    return _filaFcm;
  }

  static bool get _firebaseDisponivel =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      Firebase.apps.isNotEmpty;

  static Uri get _urlDispositivos {
    final empresasUri = Uri.parse(ApiConfig.empresas);
    final segmentos = empresasUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    if (segmentos.isNotEmpty && segmentos.last == 'empresas') {
      segmentos.removeLast();
    }
    return empresasUri.replace(
      pathSegments: [...segmentos, 'notificacoes', 'dispositivos'],
      query: null,
      fragment: null,
    );
  }

  static Future<void> registrarDispositivoFcm() =>
      _enfileirarFcm(_registrarDispositivoFcm);

  static Future<void> _registrarDispositivoFcm() async {
    if (!_firebaseDisponivel || _encerrandoSessao) return;

    try {
      final jwt = await obterTokenEmpresa();
      if (jwt == null || jwt.isEmpty) return;

      final tokenFcm = await FirebaseMessaging.instance.getToken();
      if (tokenFcm == null || tokenFcm.isEmpty) return;
      if (_encerrandoSessao || await obterTokenEmpresa() != jwt) return;

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
          'Falha ao registrar dispositivo FCM da empresa: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Erro ao registrar dispositivo FCM da empresa: $e');
    }
  }

  static Future<void> inicializarRegistroFcm() async {
    if (!_firebaseDisponivel) return;

    _tokenSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => unawaited(registrarDispositivoFcm()),
      onError: (Object erro) =>
          debugPrint('Erro ao renovar token FCM da empresa: $erro'),
    );

    await registrarDispositivoFcm();
  }

  static Future<void> _removerDispositivoFcm() async {
    if (!_firebaseDisponivel) return;

    try {
      final jwt = await obterTokenEmpresa();
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
            'Falha ao remover dispositivo FCM da empresa: ${response.statusCode}',
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Erro ao remover dispositivo FCM da empresa: $e');
    }
  }

  static Future<String?> obterTokenEmpresa() async {
    return _secureStorage.read(key: 'empresa_jwt_token');
  }

  static Future<Map<String, String>> headersAutenticados() async {
    final token = await obterTokenEmpresa();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> headersImagem() async {
    final token = await obterTokenEmpresa();

    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static MediaType tipoImagem(String nomeArquivo) {
    final nome = nomeArquivo.toLowerCase();

    if (nome.endsWith('.png')) {
      return MediaType('image', 'png');
    }

    if (nome.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }

    return MediaType('image', 'jpeg');
  }

  static String urlFotoEmpresa(String? referencia) {
    if (referencia == null || referencia.trim().isEmpty) {
      return '';
    }

    final valor = referencia.trim();

    if (valor.startsWith('http://') || valor.startsWith('https://')) {
      return valor;
    }

    return ApiConfig.urlArquivo(valor);
  }

  static Future<Uint8List?> buscarBytesFotoEmpresa(String? referencia) async {
    try {
      final url = urlFotoEmpresa(referencia);

      if (url.isEmpty) {
        return null;
      }

      final response = await http.get(
        Uri.parse(url),
        headers: await headersImagem(),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      debugPrint(
        'Erro ao carregar foto empresa. '
        'Status: ${response.statusCode}',
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao buscar imagem da empresa: $e');
      return null;
    }
  }

  static Future<void> salvarReferenciaFotoEmpresa(String? referencia) async {
    final prefs = await SharedPreferences.getInstance();

    if (referencia == null || referencia.trim().isEmpty) {
      await prefs.remove('empresa_foto');
      return;
    }

    await prefs.setString('empresa_foto', referencia.trim());
  }

  static Future<Map<String, dynamic>?> login(String email, String senha) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.empresas}/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'senha': senha}),
      );

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body));

        final token = data['token']?.toString();

        if (token == null || token.isEmpty) {
          debugPrint('Login da empresa sem token JWT.');
          return null;
        }

        _encerrandoSessao = false;
        await _secureStorage.write(key: 'empresa_jwt_token', value: token);
        unawaited(inicializarRegistroFcm());

        await salvarReferenciaFotoEmpresa(data['foto']?.toString());

        debugPrint('Login da empresa realizado e token armazenado.');

        return data;
      }

      debugPrint('Erro login empresa. Status: ${response.statusCode}');

      return null;
    } catch (e) {
      debugPrint('Erro login empresa: $e');
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
    _encerrandoSessao = true;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    await _filaFcm;
    await _removerDispositivoFcm();
    await _secureStorage.delete(key: 'empresa_jwt_token');

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('empresa_logada');
    await prefs.remove('empresa_nome');
    await prefs.remove('empresa_foto');
  }

  static Future<bool> vincularEntregador(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(empresaEmail)}/'
          'entregadores/'
          '${Uri.encodeComponent(entregadorEmail)}/solicitar',
        ),
        headers: await headersAutenticados(),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Erro ao solicitar vínculo: $e');
      return false;
    }
  }

  static Future<List<dynamic>> buscarEntregadoresPendentes() async {
    try {
      final email = await empresaLogada();

      if (email == null) return [];

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/'
          'entregadores-pendentes',
        ),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        return List<dynamic>.from(jsonDecode(response.body));
      }

      return [];
    } catch (e) {
      debugPrint('Erro ao buscar vínculos pendentes: $e');
      return [];
    }
  }

  static Future<List<dynamic>> buscarEntregadores() async {
    try {
      final email = await empresaLogada();

      if (email == null) return [];

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/entregadores',
        ),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        return List<dynamic>.from(jsonDecode(response.body));
      }

      return [];
    } catch (e) {
      debugPrint('Erro ao buscar entregadores: $e');
      return [];
    }
  }

  static Future<bool> cancelarSolicitacaoVinculo(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(empresaEmail)}/'
          'entregadores/'
          '${Uri.encodeComponent(entregadorEmail)}/'
          'cancelar-solicitacao',
        ),
        headers: await headersAutenticados(),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Erro ao cancelar solicitação de vínculo: $e');
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

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(emailAtual)}/perfil',
        ),
        headers: await headersAutenticados(),
        body: jsonEncode({'nome': nome, 'email': email}),
      );

      debugPrint(
        'Atualizar perfil empresa status: '
        '${response.statusCode}',
      );

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

      await salvarReferenciaFotoEmpresa(data['foto']?.toString());

      return data;
    } catch (e) {
      debugPrint('Erro ao atualizar perfil da empresa: $e');
      return null;
    }
  }

  static Future<int> totalEntregadores() async {
    try {
      final email = await empresaLogada();

      if (email == null) return 0;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/'
          'entregadores/total',
        ),
        headers: await headersAutenticados(),
      );

      if (response.statusCode == 200) {
        final dados = Map<String, dynamic>.from(jsonDecode(response.body));

        final total = dados['total'];

        if (total is num) {
          return total.toInt();
        }

        return int.tryParse(total?.toString() ?? '') ?? 0;
      }

      return 0;
    } catch (e) {
      debugPrint('Erro ao buscar total de entregadores: $e');
      return 0;
    }
  }

  static Future<bool> desvincularEntregador(String entregadorEmail) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) return false;

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(empresaEmail)}/'
          'desvincular/'
          '${Uri.encodeComponent(entregadorEmail)}',
        ),
        headers: await headersAutenticados(),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Erro ao desvincular: $e');
      return false;
    }
  }

  static Future<String?> atualizarFotoEmpresa(String caminhoArquivo) async {
    try {
      final email = await empresaLogada();

      if (email == null || email.isEmpty) {
        return null;
      }

      final token = await obterTokenEmpresa();

      if (token == null || token.isEmpty) {
        debugPrint('Token da empresa não encontrado.');
        return null;
      }

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/foto',
        ),
      );

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          caminhoArquivo,
          contentType: tipoImagem(caminhoArquivo),
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(body));

        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          return null;
        }

        await salvarReferenciaFotoEmpresa(foto);

        return foto;
      }

      debugPrint(
        'Erro foto empresa status: '
        '${response.statusCode}. '
        'Resposta: $body',
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao enviar foto da empresa: $e');
      return null;
    }
  }

  static Future<String?> atualizarFotoEmpresaBytes({
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    try {
      final email = await empresaLogada();
      final token = await obterTokenEmpresa();

      if (email == null ||
          email.isEmpty ||
          token == null ||
          token.isEmpty ||
          bytes.isEmpty) {
        return null;
      }

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse(
          '${ApiConfig.empresas}/'
          '${Uri.encodeComponent(email)}/foto',
        ),
      );

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        http.MultipartFile.fromBytes(
          'foto',
          bytes,
          filename: nomeArquivo,
          contentType: tipoImagem(nomeArquivo),
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(body));

        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          return null;
        }

        await salvarReferenciaFotoEmpresa(foto);

        return foto;
      }

      debugPrint(
        'Erro ao enviar foto por bytes. '
        'Status: ${response.statusCode}. '
        'Resposta: $body',
      );

      return null;
    } catch (e) {
      debugPrint('Erro ao enviar foto por bytes: $e');
      return null;
    }
  }

  static Future<String?> fotoEmpresa() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('empresa_foto');
  }

  static Future<bool> confirmarCadastro(String email, String codigo) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.empresas}/confirmar-cadastro'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'codigo': codigo.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'Confirmação de cadastro empresa status: ${response.statusCode}',
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Erro ao confirmar cadastro empresa: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> _requisicaoRecuperacao(
    String metodo,
    String endpoint,
    Map<String, String> dados,
  ) async {
    try {
      final uri = Uri.parse('${ApiConfig.empresas}/$endpoint');
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

      String mensagem = response.statusCode >= 200 && response.statusCode < 300
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
      debugPrint('Erro na recuperação de senha da empresa: $e');
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

  static Future<bool> cadastrar(String nome, String email, String senha) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.empresas}/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'nome': nome, 'email': email, 'senha': senha}),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('Cadastro empresa status: ${response.statusCode}');

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Erro cadastro empresa: $e');
      return false;
    }
  }
}
