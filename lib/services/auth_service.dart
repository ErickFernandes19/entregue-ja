import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'api_service.dart';

class AuthService {
  static const Duration _tempoLimite = Duration(seconds: 20);
  static const Duration _tempoLimiteUpload = Duration(seconds: 60);

  static const ApiException _sessaoExpirada = ApiException(
    'Sua sessão expirou. Entre novamente na sua conta.',
    statusCode: 401,
  );

  static T _tratarFalha<T>(
    Object erro,
    T retorno, {
    required bool lancarErro,
    required String mensagemPadrao,
  }) {
    debugPrint('$mensagemPadrao (${erro.runtimeType})');
    if (lancarErro) {
      if (erro is ApiException) throw erro;
      throw ApiException(
        ApiService.mensagemErro(erro, mensagemPadrao: mensagemPadrao),
      );
    }
    return retorno;
  }

  static String _corpo(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  static void _validarResposta(http.Response response) {
    if (response.statusCode != 200) {
      throw ApiService.erroHttp(response.statusCode, _corpo(response));
    }
  }

  static Map<String, dynamic> _decodificarMapa(String corpo) {
    final dados = jsonDecode(corpo);
    if (dados is Map<String, dynamic>) return dados;
    throw const FormatException('Resposta inválida do servidor.');
  }

  static String _mensagemPublica(http.Response response) {
    if (response.statusCode == 401) {
      return 'Não foi possível validar a solicitação. Confira os dados informados.';
    }
    return ApiService.erroHttp(response.statusCode, _corpo(response)).mensagem;
  }

  static String _mensagemSucesso(http.Response response, String padrao) {
    try {
      final dados = jsonDecode(_corpo(response));
      if (dados is Map && dados['mensagem'] is String) {
        final mensagem = (dados['mensagem'] as String).trim();
        if (mensagem.isNotEmpty && mensagem.length <= 300) return mensagem;
      }
    } on FormatException {
      return padrao;
    }
    return padrao;
  }

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static StreamSubscription<String>? _tokenSubscription;
  static Future<void> _filaFcm = Future<void>.value();
  static final ValueNotifier<bool> _estadoEncerramento = ValueNotifier(false);

  static ValueListenable<bool> get encerrandoSessao => _estadoEncerramento;

  static bool get _encerrandoSessao => _estadoEncerramento.value;

  static Future<void> _enfileirarFcm(Future<void> Function() operacao) {
    final proxima = _filaFcm.then((_) => operacao());
    _filaFcm = proxima.catchError((Object erro) {
      debugPrint('Erro na operação FCM do entregador: $erro');
    });
    return proxima;
  }

  static const String _chaveVapid =
      'BJSQHCGoeyvu-Za4k1aR_LFVP2A1W3895Pyws5yV4kvuB9BvwfUK2CikQDbzAldyjPNZ2CshUhgdkg1MF8p-V5o';

  static bool get _firebaseDisponivel =>
      (kIsWeb || defaultTargetPlatform == TargetPlatform.android) &&
      Firebase.apps.isNotEmpty;

  static Future<String?> _obterTokenFcm() async {
    if (kIsWeb) {
      final permissao = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (permissao.authorizationStatus != AuthorizationStatus.authorized) {
        return null;
      }
    }
    return FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb ? _chaveVapid : null,
    );
  }

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

  static Future<void> registrarDispositivoFcm() async {
    try {
      await _enfileirarFcm(_registrarDispositivoFcmConfirmado);
    } catch (erro) {
      debugPrint('Erro ao registrar dispositivo FCM: $erro');
    }
  }

  static Future<void> registrarDispositivoFcmConfirmado() =>
      _enfileirarFcm(_registrarDispositivoFcmConfirmado);

  static Future<void> _registrarDispositivoFcmConfirmado() async {
    if (!_firebaseDisponivel) {
      throw StateError('Firebase não está disponível neste dispositivo.');
    }
    if (_encerrandoSessao) {
      throw StateError('A sessão está sendo encerrada.');
    }

    final jwt = await obterToken();
    if (jwt == null || jwt.isEmpty) {
      throw StateError('Faça login novamente para ativar as notificações.');
    }

    final tokenFcm = await _obterTokenFcm();
    if (tokenFcm == null || tokenFcm.isEmpty) {
      throw StateError('Não foi possível obter o token de notificações.');
    }
    if (_encerrandoSessao || await obterToken() != jwt) {
      throw StateError('A sessão foi alterada durante o registro.');
    }

    final response = await http
        .post(
          _urlDispositivos,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({
            'token': tokenFcm,
            'plataforma': kIsWeb ? 'WEB' : 'ANDROID',
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw StateError(
        'O servidor recusou o registro FCM (HTTP ${response.statusCode}).',
      );
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

      final tokenFcm = await _obterTokenFcm();
      if (tokenFcm == null || tokenFcm.isEmpty) return;

      final request = http.Request('DELETE', _urlDispositivos)
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        })
        ..body = jsonEncode({
          'token': tokenFcm,
          'plataforma': kIsWeb ? 'WEB' : 'ANDROID',
        });

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

  static Future<Map<String, dynamic>?> login(
    String email,
    String senha, {
    bool lancarErro = false,
  }) async {
    try {
      debugPrint('Tentando login...');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.auth}/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'senha': senha}),
          )
          .timeout(_tempoLimite);

      debugPrint('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = _decodificarMapa(_corpo(response));

        final token = data['token']?.toString();

        if (token == null || token.isEmpty) {
          throw const FormatException('Token ausente na resposta.');
        }

        await _secureStorage.write(key: 'jwt_token', value: token);
        _estadoEncerramento.value = false;
        unawaited(inicializarRegistroFcm());

        debugPrint('Login realizado e token armazenado.');

        return data;
      }

      if (response.statusCode == 401) {
        throw const ApiException('E-mail ou senha inválidos.', statusCode: 401);
      }
      throw ApiService.erroHttp(response.statusCode, _corpo(response));
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível entrar na conta.',
      );
    }
  }

  static Future<Map<String, dynamic>?> buscarVinculoPendente({
    bool lancarErro = false,
  }) async {
    try {
      final email = await usuarioLogado();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.auth}/${Uri.encodeComponent(email)}/vinculo-pendente',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      if (response.statusCode == 200) {
        return _decodificarMapa(_corpo(response));
      }

      throw ApiService.erroHttp(response.statusCode, _corpo(response));
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível consultar a solicitação de vínculo.',
      );
    }
  }

  static Future<Map<String, dynamic>?> buscarPerfil({
    bool lancarErro = false,
  }) async {
    try {
      final email = await usuarioLogado();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .get(
            Uri.parse('${ApiConfig.auth}/${Uri.encodeComponent(email)}/perfil'),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      if (response.statusCode == 200) {
        return _decodificarMapa(_corpo(response));
      }

      throw ApiService.erroHttp(response.statusCode, _corpo(response));
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível carregar o perfil.',
      );
    }
  }

  static Future<String?> atualizarFotoPerfil(
    String caminhoArquivo, {
    bool lancarErro = false,
  }) async {
    try {
      final email = await usuarioLogado();

      if (email == null) throw _sessaoExpirada;

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.auth}/${Uri.encodeComponent(email)}/foto'),
      );

      final token = await obterToken();

      if (token == null || token.isEmpty) throw _sessaoExpirada;
      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        await http.MultipartFile.fromPath('foto', caminhoArquivo),
      );

      final response = await request.send().timeout(_tempoLimiteUpload);
      final body = await response.stream
          .bytesToString(utf8)
          .timeout(_tempoLimiteUpload);

      if (response.statusCode == 200) {
        final data = _decodificarMapa(body);

        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          throw const FormatException('Foto ausente na resposta.');
        }

        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('usuario_foto', foto);

        return foto;
      }

      throw ApiService.erroHttp(response.statusCode, body);
    } catch (e) {
      return _tratarFalha<String?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível atualizar a foto do perfil.',
      );
    }
  }

  static Future<String?> atualizarFotoPerfilBytes({
    required Uint8List bytes,
    required String nomeArquivo,
    bool lancarErro = false,
  }) async {
    try {
      final email = await usuarioLogado();
      final token = await obterToken();

      if (email == null || email.isEmpty || token == null || token.isEmpty) {
        throw _sessaoExpirada;
      }
      if (bytes.isEmpty) {
        throw const ApiException('Selecione uma foto válida.');
      }

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('${ApiConfig.auth}/${Uri.encodeComponent(email)}/foto'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile.fromBytes('foto', bytes, filename: nomeArquivo),
      );

      final response = await request.send().timeout(_tempoLimiteUpload);
      final body = await response.stream
          .bytesToString(utf8)
          .timeout(_tempoLimiteUpload);

      if (response.statusCode == 200) {
        final data = _decodificarMapa(body);
        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          throw const FormatException('Foto ausente na resposta.');
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('usuario_foto', foto);
        return foto;
      }

      throw ApiService.erroHttp(response.statusCode, body);
    } catch (e) {
      return _tratarFalha<String?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível atualizar a foto do perfil.',
      );
    }
  }

  static Future<String?> fotoUsuario() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('usuario_foto');
  }

  static Future<bool> aceitarVinculo({bool lancarErro = false}) async {
    try {
      final email = await usuarioLogado();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.auth}/${Uri.encodeComponent(email)}/aceitar-vinculo',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      return true;
    } catch (e) {
      return _tratarFalha<bool>(
        e,
        false,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível aceitar o vínculo.',
      );
    }
  }

  static Future<bool> recusarVinculo({bool lancarErro = false}) async {
    try {
      final email = await usuarioLogado();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.auth}/${Uri.encodeComponent(email)}/recusar-vinculo',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      return true;
    } catch (e) {
      return _tratarFalha<bool>(
        e,
        false,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível recusar o vínculo.',
      );
    }
  }

  static Future<Map<String, dynamic>> desvincularEmpresa({
    required String empresaEmail,
  }) async {
    final empresa = empresaEmail.trim();
    if (empresa.isEmpty) {
      return {
        'sucesso': false,
        'mensagem':
            'Não foi possível identificar a empresa vinculada. Atualize o perfil.',
      };
    }

    try {
      final token = await obterToken();
      final email = await usuarioLogado();
      if (email == null ||
          token == null ||
          token.isEmpty ||
          _encerrandoSessao ||
          await obterToken() != token) {
        return {
          'sucesso': false,
          'mensagem': 'Sua sessão não está disponível. Faça login novamente.',
        };
      }

      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.auth}/${Uri.encodeComponent(email)}/desvincular',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'empresaEmail': empresa}),
          )
          .timeout(const Duration(seconds: 20));

      if (_encerrandoSessao || await obterToken() != token) {
        return {
          'sucesso': false,
          'mensagem':
              'Sua sessão foi alterada. Atualize o perfil para consultar o vínculo.',
        };
      }

      final status = response.statusCode;
      final sucesso = status == 200;
      String mensagem = switch (status) {
        200 => 'Vínculo encerrado com sucesso.',
        400 => 'Não foi possível validar a solicitação. Atualize o perfil.',
        401 => 'Sua sessão expirou. Faça login novamente.',
        403 => 'Você não tem permissão para encerrar este vínculo.',
        404 => 'Vínculo não encontrado. Atualize o perfil.',
        409 =>
          'Não foi possível encerrar o vínculo. Verifique suas entregas e atualize o perfil.',
        _ =>
          'Não foi possível confirmar o encerramento do vínculo. Atualize o perfil antes de tentar novamente.',
      };

      if (sucesso) {
        mensagem = _mensagemSucesso(response, mensagem);
      } else if (status == 400 || status == 403 || status == 409) {
        mensagem = ApiService.erroHttp(status, _corpo(response)).mensagem;
      }

      return {'sucesso': sucesso, 'mensagem': mensagem, 'statusCode': status};
    } on TimeoutException {
      return {
        'sucesso': false,
        'mensagem':
            'O servidor demorou para responder. Atualize o perfil para verificar se o vínculo foi encerrado.',
      };
    } catch (e) {
      debugPrint('Erro ao desvincular empresa: $e');
      return {
        'sucesso': false,
        'mensagem':
            'Não foi possível confirmar o encerramento do vínculo. Verifique sua conexão e atualize o perfil.',
      };
    }
  }

  static Future<Map<String, dynamic>?> buscarEmpresaVinculada({
    bool lancarErro = false,
  }) async {
    try {
      final email = await usuarioLogado();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.auth}/${Uri.encodeComponent(email)}/empresa-vinculada',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      if (response.statusCode == 200) {
        return _decodificarMapa(_corpo(response));
      }

      throw ApiService.erroHttp(response.statusCode, _corpo(response));
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível consultar a empresa vinculada.',
      );
    }
  }

  static Future<bool> atualizarConfiguracoesVeiculo({
    required String veiculo,
    required String capacidadeCarga,
    bool lancarErro = false,
  }) async {
    try {
      final email = await usuarioLogado();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.auth}/${Uri.encodeComponent(email)}/configuracoes-veiculo',
            ),
            headers: await headersAutenticados(),
            body: jsonEncode({
              'veiculo': veiculo,
              'capacidadeCarga': capacidadeCarga,
            }),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      return true;
    } catch (e) {
      return _tratarFalha<bool>(
        e,
        false,
        lancarErro: lancarErro,
        mensagemPadrao:
            'Não foi possível atualizar as configurações do veículo.',
      );
    }
  }

  static Future<Map<String, dynamic>> _requisicaoCadastro(
    String endpoint,
    Map<String, String> dados,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.auth}/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(dados),
          )
          .timeout(const Duration(seconds: 15));

      final sucesso = response.statusCode >= 200 && response.statusCode < 300;
      final mensagem = sucesso
          ? _mensagemSucesso(response, 'Solicitação realizada com sucesso.')
          : _mensagemPublica(response);
      return {'sucesso': sucesso, 'mensagem': mensagem};
    } catch (e) {
      debugPrint('Erro no cadastro ($endpoint): ${e.runtimeType}');
      return {
        'sucesso': false,
        'mensagem': ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível concluir a solicitação.',
        ),
      };
    }
  }

  static Future<Map<String, dynamic>> cadastrarComResultado(
    String nome,
    String email,
    String senha,
  ) {
    return _requisicaoCadastro('register', {
      'nome': nome.trim(),
      'email': email.trim().toLowerCase(),
      'senha': senha,
    });
  }

  static Future<bool> cadastrar(String nome, String email, String senha) async {
    final resultado = await cadastrarComResultado(nome, email, senha);
    return resultado['sucesso'] == true;
  }

  static Future<Map<String, dynamic>> confirmarCadastroComResultado(
    String email,
    String codigo,
  ) {
    return _requisicaoCadastro('confirmar-cadastro', {
      'email': email.trim().toLowerCase(),
      'codigo': codigo.trim(),
    });
  }

  static Future<bool> confirmarCadastro(String email, String codigo) async {
    final resultado = await confirmarCadastroComResultado(email, codigo);
    return resultado['sucesso'] == true;
  }

  static Future<Map<String, dynamic>> reenviarCodigoCadastro(String email) {
    return _requisicaoCadastro('reenviar-codigo', {
      'email': email.trim().toLowerCase(),
    });
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

      final sucesso = response.statusCode >= 200 && response.statusCode < 300;
      final mensagem = sucesso
          ? _mensagemSucesso(response, 'Operação realizada com sucesso.')
          : _mensagemPublica(response);
      return {'sucesso': sucesso, 'mensagem': mensagem};
    } catch (e) {
      debugPrint('Erro na recuperação de senha: ${e.runtimeType}');
      return {
        'sucesso': false,
        'mensagem': ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível concluir a recuperação de senha.',
        ),
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
    bool lancarErro = false,
  }) async {
    try {
      final emailAtual = await usuarioLogado();

      if (emailAtual == null) throw _sessaoExpirada;

      final emailAtualUrl = Uri.encodeComponent(emailAtual);

      final response = await http
          .put(
            Uri.parse('${ApiConfig.auth}/$emailAtualUrl/perfil'),
            headers: await headersAutenticados(),
            body: jsonEncode({'nome': nome, 'email': email}),
          )
          .timeout(_tempoLimite);

      debugPrint('Atualizar perfil status: ${response.statusCode}');

      _validarResposta(response);

      final data = _decodificarMapa(_corpo(response));

      final novoNome = data['nome']?.toString();
      final novoEmail = data['email']?.toString();

      if (novoNome == null || novoEmail == null) {
        throw const FormatException('Perfil incompleto na resposta.');
      }

      await salvarUsuario(novoEmail, novoNome);

      return data;
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível atualizar o perfil.',
      );
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

  static bool _tokenJwtValido(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return false;

      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
      );

      if (payload is! Map) return false;

      final expiracao = payload['exp'];
      final segundos = expiracao is num
          ? expiracao.toInt()
          : int.tryParse(expiracao?.toString() ?? '');

      if (segundos == null) return false;

      final agora = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      return segundos > agora;
    } catch (e) {
      debugPrint('Erro ao verificar validade do JWT do entregador: $e');
      return false;
    }
  }

  static Future<String?> usuarioLogado() async {
    if (_encerrandoSessao) return null;

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('usuario_logado');

    if (email == null || email.trim().isEmpty) return null;

    try {
      final token = await obterToken();
      if (_encerrandoSessao ||
          token == null ||
          token.isEmpty ||
          !_tokenJwtValido(token)) {
        return null;
      }

      return email;
    } catch (e) {
      debugPrint('Erro ao verificar sessão do entregador: $e');
      return null;
    }
  }

  static Future<void> logout() async {
    _estadoEncerramento.value = true;
    try {
      await _tokenSubscription?.cancel();
      await _filaFcm;
      await _removerDispositivoFcm();
    } finally {
      _tokenSubscription = null;
      await _secureStorage.delete(key: 'jwt_token');

      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('usuario_logado');
      await prefs.remove('usuario_nome');
      await prefs.remove('usuario_foto');
    }
  }
}
