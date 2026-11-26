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
import 'api_service.dart';

class EmpresaService {
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
  static bool _encerrandoSessao = false;

  static Future<void> _enfileirarFcm(Future<void> Function() operacao) {
    final proxima = _filaFcm.then((_) => operacao());
    _filaFcm = proxima.catchError((Object erro) {
      debugPrint('Erro na operação FCM da empresa: $erro');
    });
    return _filaFcm;
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

  static Future<void> registrarDispositivoFcmConfirmado() {
    final operacao = _filaFcm.then((_) => _registrarDispositivoFcmEstrito());
    _filaFcm = operacao.catchError((Object erro) {
      debugPrint('Erro na operação FCM da empresa: $erro');
    });
    return operacao;
  }

  static Future<void> _registrarDispositivoFcm() async {
    try {
      await _registrarDispositivoFcmEstrito();
    } catch (e) {
      debugPrint('Erro ao registrar dispositivo FCM da empresa: $e');
    }
  }

  static Future<void> _registrarDispositivoFcmEstrito() async {
    if (!_firebaseDisponivel) {
      throw StateError('Firebase não está disponível neste dispositivo.');
    }
    if (_encerrandoSessao) {
      throw StateError('A sessão da empresa está sendo encerrada.');
    }

    final jwt = await obterTokenEmpresa();
    if (jwt == null || jwt.isEmpty) {
      throw StateError('A empresa precisa estar autenticada.');
    }

    final tokenFcm = await _obterTokenFcm();
    if (tokenFcm == null || tokenFcm.isEmpty) {
      throw StateError('Não foi possível obter o token de notificações.');
    }
    if (_encerrandoSessao || await obterTokenEmpresa() != jwt) {
      throw StateError('A sessão da empresa foi alterada.');
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

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw StateError(
        'O servidor não confirmou o registro FCM (HTTP ${response.statusCode}).',
      );
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

  static Future<Uint8List?> buscarBytesFotoEmpresa(
    String? referencia, {
    bool lancarErro = false,
  }) async {
    try {
      final url = urlFotoEmpresa(referencia);

      if (url.isEmpty) {
        return null;
      }

      final uri = Uri.parse(url);
      final api = Uri.parse(ApiConfig.empresas);
      if ((uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const ApiException('Endereço da foto inválido.');
      }

      final mesmaOrigem =
          uri.scheme == api.scheme &&
          uri.host == api.host &&
          uri.port == api.port;
      final request = http.Request('GET', uri);
      if (mesmaOrigem) {
        request.followRedirects = false;
        request.headers.addAll(await headersImagem());
      }

      final client = http.Client();
      try {
        final response = await client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(_tempoLimite);
        _validarResposta(response);
        return response.bodyBytes;
      } finally {
        client.close();
      }
    } catch (e) {
      return _tratarFalha<Uint8List?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível carregar a foto da empresa.',
      );
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

  static Future<Map<String, dynamic>?> login(
    String email,
    String senha, {
    bool lancarErro = false,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.empresas}/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'senha': senha}),
          )
          .timeout(_tempoLimite);

      if (response.statusCode == 200) {
        final data = _decodificarMapa(_corpo(response));

        final token = data['token']?.toString();

        if (token == null || token.isEmpty) {
          throw const FormatException('Token ausente na resposta.');
        }

        _encerrandoSessao = false;
        await _secureStorage.write(key: 'empresa_jwt_token', value: token);
        unawaited(inicializarRegistroFcm());

        await salvarReferenciaFotoEmpresa(data['foto']?.toString());

        debugPrint('Login da empresa realizado e token armazenado.');

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
        mensagemPadrao: 'Não foi possível entrar na sua conta.',
      );
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

  static bool _tokenValido(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return false;

      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
      );
      if (payload is! Map<String, dynamic>) return false;

      final expiracao = payload['exp'];
      if (expiracao is! num) return false;

      final agora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return expiracao > agora;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> empresaLogada() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('empresa_logada');
    if (email == null || email.trim().isEmpty) return null;

    try {
      final token = await obterTokenEmpresa();
      if (token == null || !_tokenValido(token)) return null;
      return email;
    } catch (e) {
      debugPrint('Erro ao verificar sessão da empresa: $e');
      return null;
    }
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

  static Future<bool> vincularEntregador(
    String entregadorEmail, {
    bool lancarErro = false,
  }) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) throw _sessaoExpirada;

      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.empresas}/'
              '${Uri.encodeComponent(empresaEmail)}/'
              'entregadores/'
              '${Uri.encodeComponent(entregadorEmail)}/solicitar',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      return true;
    } catch (e) {
      return _tratarFalha(
        e,
        false,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível solicitar o vínculo.',
      );
    }
  }

  static Future<List<dynamic>> buscarEntregadoresPendentes({
    bool lancarErro = false,
  }) async {
    try {
      final email = await empresaLogada();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.empresas}/'
              '${Uri.encodeComponent(email)}/'
              'entregadores-pendentes',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      final dados = jsonDecode(_corpo(response));
      if (dados is List) return List<dynamic>.from(dados);
      throw const FormatException('Lista inválida do servidor.');
    } catch (e) {
      return _tratarFalha(
        e,
        <dynamic>[],
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível buscar as solicitações pendentes.',
      );
    }
  }

  static Future<List<dynamic>> buscarEntregadores({
    bool lancarErro = false,
  }) async {
    try {
      final email = await empresaLogada();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.empresas}/'
              '${Uri.encodeComponent(email)}/entregadores',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      final dados = jsonDecode(_corpo(response));
      if (dados is List) return List<dynamic>.from(dados);
      throw const FormatException('Lista inválida do servidor.');
    } catch (e) {
      return _tratarFalha(
        e,
        <dynamic>[],
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível buscar os entregadores.',
      );
    }
  }

  static Future<bool> cancelarSolicitacaoVinculo(
    String entregadorEmail, {
    bool lancarErro = false,
  }) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) throw _sessaoExpirada;

      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.empresas}/'
              '${Uri.encodeComponent(empresaEmail)}/'
              'entregadores/'
              '${Uri.encodeComponent(entregadorEmail)}/'
              'cancelar-solicitacao',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      return true;
    } catch (e) {
      return _tratarFalha(
        e,
        false,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível cancelar a solicitação de vínculo.',
      );
    }
  }

  static Future<Map<String, dynamic>?> atualizarPerfilEmpresa({
    required String nome,
    required String email,
    bool lancarErro = false,
  }) async {
    try {
      final emailAtual = await empresaLogada();

      if (emailAtual == null || emailAtual.isEmpty) {
        throw _sessaoExpirada;
      }

      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.empresas}/'
              '${Uri.encodeComponent(emailAtual)}/perfil',
            ),
            headers: await headersAutenticados(),
            body: jsonEncode({'nome': nome, 'email': email}),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);

      final data = _decodificarMapa(_corpo(response));

      final novoNome = data['nome']?.toString();
      final novoEmail = data['email']?.toString();

      if (novoNome == null || novoEmail == null) {
        throw const FormatException('Dados do perfil ausentes.');
      }

      await salvarDadosEmpresa(email: novoEmail, nome: novoNome);

      await salvarReferenciaFotoEmpresa(data['foto']?.toString());

      return data;
    } catch (e) {
      return _tratarFalha<Map<String, dynamic>?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível atualizar o perfil da empresa.',
      );
    }
  }

  static Future<int> totalEntregadores({bool lancarErro = false}) async {
    try {
      final email = await empresaLogada();

      if (email == null) throw _sessaoExpirada;

      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.empresas}/'
              '${Uri.encodeComponent(email)}/'
              'entregadores/total',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      final dados = _decodificarMapa(_corpo(response));
      final total = dados['total'];
      if (total is num) return total.toInt();
      final valor = int.tryParse(total?.toString() ?? '');
      if (valor != null) return valor;
      throw const FormatException('Total de entregadores inválido.');
    } catch (e) {
      return _tratarFalha(
        e,
        0,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível consultar o total de entregadores.',
      );
    }
  }

  static Future<bool> desvincularEntregador(
    String entregadorEmail, {
    bool lancarErro = false,
  }) async {
    try {
      final empresaEmail = await empresaLogada();

      if (empresaEmail == null) throw _sessaoExpirada;

      final response = await http
          .put(
            Uri.parse(
              '${ApiConfig.empresas}/'
              '${Uri.encodeComponent(empresaEmail)}/'
              'desvincular/'
              '${Uri.encodeComponent(entregadorEmail)}',
            ),
            headers: await headersAutenticados(),
          )
          .timeout(_tempoLimite);

      _validarResposta(response);
      return true;
    } catch (e) {
      return _tratarFalha(
        e,
        false,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível desvincular o entregador.',
      );
    }
  }

  static Future<String?> atualizarFotoEmpresa(
    String caminhoArquivo, {
    bool lancarErro = false,
  }) async {
    try {
      final email = await empresaLogada();

      if (email == null || email.isEmpty) {
        throw _sessaoExpirada;
      }

      final token = await obterTokenEmpresa();

      if (token == null || token.isEmpty) {
        throw _sessaoExpirada;
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

      final response = await request.send().timeout(_tempoLimiteUpload);
      final bytesResposta = await response.stream.toBytes().timeout(
        _tempoLimiteUpload,
      );
      final body = utf8.decode(bytesResposta, allowMalformed: true);

      if (response.statusCode == 200) {
        final data = _decodificarMapa(body);

        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          throw const FormatException('Referência da foto ausente.');
        }

        await salvarReferenciaFotoEmpresa(foto);

        return foto;
      }

      throw ApiService.erroHttp(response.statusCode, body);
    } catch (e) {
      return _tratarFalha<String?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível atualizar a foto da empresa.',
      );
    }
  }

  static Future<String?> atualizarFotoEmpresaBytes({
    required Uint8List bytes,
    required String nomeArquivo,
    bool lancarErro = false,
  }) async {
    try {
      final email = await empresaLogada();
      final token = await obterTokenEmpresa();

      if (email == null || email.isEmpty || token == null || token.isEmpty) {
        throw _sessaoExpirada;
      }
      if (bytes.isEmpty) {
        throw const ApiException('Selecione uma foto válida.');
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

      final response = await request.send().timeout(_tempoLimiteUpload);
      final bytesResposta = await response.stream.toBytes().timeout(
        _tempoLimiteUpload,
      );
      final body = utf8.decode(bytesResposta, allowMalformed: true);

      if (response.statusCode == 200) {
        final data = _decodificarMapa(body);

        final foto = data['foto']?.toString();

        if (foto == null || foto.isEmpty) {
          throw const FormatException('Referência da foto ausente.');
        }

        await salvarReferenciaFotoEmpresa(foto);

        return foto;
      }

      throw ApiService.erroHttp(response.statusCode, body);
    } catch (e) {
      return _tratarFalha<String?>(
        e,
        null,
        lancarErro: lancarErro,
        mensagemPadrao: 'Não foi possível atualizar a foto da empresa.',
      );
    }
  }

  static Future<String?> fotoEmpresa() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('empresa_foto');
  }

  static Future<bool> confirmarCadastro(String email, String codigo) async {
    final resultado = await confirmarCadastroComResultado(email, codigo);
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

  static Future<Map<String, dynamic>> reenviarCodigoCadastro(String email) {
    return _requisicaoCadastro('reenviar-codigo', {
      'email': email.trim().toLowerCase(),
    });
  }

  static Future<Map<String, dynamic>> _requisicaoCadastro(
    String endpoint,
    Map<String, String> dados,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.empresas}/$endpoint'),
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

  static Future<bool> cadastrar(String nome, String email, String senha) async {
    final resultado = await cadastrarComResultado(nome, email, senha);
    return resultado['sucesso'] == true;
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
}
