import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'empresa_service.dart';

enum TipoContaAssinatura { empresa, entregador }

class AssinaturaException extends ApiException {
  const AssinaturaException(super.mensagem, {super.statusCode});
}

class _SessaoAssinatura {
  final TipoContaAssinatura tipoConta;
  final String token;

  const _SessaoAssinatura(this.tipoConta, this.token);

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };
}

class AssinaturaService {
  static const Duration _tempoLimite = Duration(seconds: 15);
  static bool _ativandoTeste = false;

  static Uri get _urlBase => Uri.parse('${ApiConfig.baseUrl}/assinaturas');

  static String? _normalizarToken(String? token) {
    final valor = token?.trim();
    return valor == null || valor.isEmpty ? null : valor;
  }

  static Future<String?> _obterToken(TipoContaAssinatura tipoConta) async {
    final token = tipoConta == TipoContaAssinatura.empresa
        ? await EmpresaService.obterTokenEmpresa()
        : await AuthService.obterToken();
    return _normalizarToken(token);
  }

  static Future<String?> _obterEmail(TipoContaAssinatura tipoConta) {
    return tipoConta == TipoContaAssinatura.empresa
        ? EmpresaService.empresaLogada()
        : AuthService.usuarioLogado();
  }

  static AssinaturaException _sessaoIndisponivel(TipoContaAssinatura? tipo) {
    final mensagem = switch (tipo) {
      TipoContaAssinatura.empresa =>
        'Sua sessão empresarial expirou ou não está disponível. Faça login como empresa novamente.',
      TipoContaAssinatura.entregador =>
        'Sua sessão expirou ou não está disponível. Faça login como entregador novamente.',
      null => 'Sua sessão não está disponível. Faça login novamente.',
    };
    return AssinaturaException(mensagem, statusCode: 401);
  }

  static Future<_SessaoAssinatura> _obterSessao({
    TipoContaAssinatura? tipoConta,
  }) async {
    final TipoContaAssinatura tipo;
    final String? token;

    if (tipoConta != null) {
      tipo = tipoConta;
      token = await _obterToken(tipo);
    } else {
      final tokenEmpresa = await _obterToken(TipoContaAssinatura.empresa);
      final tokenEntregador = await _obterToken(TipoContaAssinatura.entregador);

      if (tokenEmpresa != null && tokenEntregador != null) {
        throw const AssinaturaException(
          'Existem duas sessões disponíveis. Selecione o perfil correto para consultar a assinatura.',
          statusCode: 409,
        );
      }
      if (tokenEmpresa == null && tokenEntregador == null) {
        throw _sessaoIndisponivel(null);
      }
      tipo = tokenEmpresa != null
          ? TipoContaAssinatura.empresa
          : TipoContaAssinatura.entregador;
      token = tokenEmpresa ?? tokenEntregador;
    }

    if (token == null) {
      throw _sessaoIndisponivel(tipo);
    }
    final email = await _obterEmail(tipo);
    if (email == null || email.trim().isEmpty) {
      throw _sessaoIndisponivel(tipo);
    }
    if (await _obterToken(tipo) != token) {
      throw const AssinaturaException(
        'Sua sessão foi alterada. Atualize os dados da assinatura.',
        statusCode: 401,
      );
    }

    return _SessaoAssinatura(tipo, token);
  }

  static Future<void> _conferirSessao(
    _SessaoAssinatura sessao,
    TipoContaAssinatura? tipoConta,
  ) async {
    final atual = await _obterSessao(tipoConta: tipoConta);
    if (atual.tipoConta != sessao.tipoConta || atual.token != sessao.token) {
      throw const AssinaturaException(
        'Sua sessão foi alterada. Atualize os dados da assinatura.',
        statusCode: 401,
      );
    }
  }

  static Future<http.Response> _requisitar(
    String caminho,
    _SessaoAssinatura sessao, {
    bool post = false,
  }) async {
    final client = http.Client();
    try {
      final request =
          http.Request(post ? 'POST' : 'GET', Uri.parse('$_urlBase/$caminho'))
            ..headers.addAll(sessao.headers)
            ..followRedirects = false;
      return await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_tempoLimite);
    } on TimeoutException {
      throw AssinaturaException(
        post
            ? 'O servidor demorou para responder. Consulte sua assinatura antes de tentar novamente.'
            : 'O servidor demorou para responder. Tente novamente.',
      );
    } on http.ClientException {
      throw AssinaturaException(
        post
            ? 'Não foi possível conectar ao servidor. Consulte sua assinatura antes de tentar novamente.'
            : 'Não foi possível conectar ao servidor. Verifique sua conexão.',
      );
    } catch (e) {
      throw AssinaturaException(
        post
            ? 'Não foi possível confirmar a ativação. Consulte sua assinatura antes de tentar novamente.'
            : ApiService.mensagemErro(
                e,
                mensagemPadrao: 'Não foi possível consultar sua assinatura.',
              ),
      );
    } finally {
      client.close();
    }
  }

  static dynamic _decodificar(http.Response response) {
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static void _verificarStatus(http.Response response, {bool post = false}) {
    final status = response.statusCode;
    if (status == 200 || (post && status == 201)) {
      return;
    }

    final erro = ApiService.erroHttp(
      status,
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    var mensagem = erro.mensagem;

    if (status == 404 && mensagem == ApiService.erroHttp(status, '').mensagem) {
      mensagem = 'Nenhuma assinatura foi encontrada.';
    }
    if (post) {
      if (status == 409 &&
          mensagem == ApiService.erroHttp(status, '').mensagem) {
        mensagem = 'O teste gratuito não está disponível ou já foi utilizado.';
      }
      if (status >= 500 || status == 408 || (status >= 200 && status < 400)) {
        mensagem =
            '$mensagem Consulte sua assinatura antes de tentar novamente.';
      }
    }

    throw AssinaturaException(mensagem, statusCode: status);
  }

  static void _validarTipoConta(
    Map<String, dynamic> dados,
    _SessaoAssinatura sessao, {
    required bool obrigatorio,
  }) {
    final informado = dados['tipoConta'];
    if (informado == null && !obrigatorio) return;
    final esperado = sessao.tipoConta == TipoContaAssinatura.empresa
        ? 'EMPRESA'
        : 'ENTREGADOR';

    if (informado != esperado) {
      throw const AssinaturaException(
        'O servidor retornou dados de um perfil diferente do solicitado.',
      );
    }
  }

  static Map<String, dynamic> _validarMapa(
    dynamic dados,
    _SessaoAssinatura sessao, {
    required bool tipoObrigatorio,
  }) {
    if (dados is! Map<String, dynamic>) {
      throw const FormatException('Formato de resposta inválido.');
    }
    _validarTipoConta(dados, sessao, obrigatorio: tipoObrigatorio);
    return dados;
  }

  static Future<T> _consultar<T>(
    String caminho,
    TipoContaAssinatura? tipoConta,
    T Function(http.Response, _SessaoAssinatura) interpretar,
  ) async {
    try {
      final sessao = await _obterSessao(tipoConta: tipoConta);
      final response = await _requisitar(caminho, sessao);
      await _conferirSessao(sessao, tipoConta);
      return interpretar(response, sessao);
    } on AssinaturaException {
      rethrow;
    } on ApiException catch (e) {
      throw AssinaturaException(e.mensagem, statusCode: e.statusCode);
    } catch (e) {
      throw AssinaturaException(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível consultar sua assinatura.',
        ),
      );
    }
  }

  static Future<Map<String, dynamic>?> buscarAtual({
    TipoContaAssinatura? tipoConta,
  }) {
    return _consultar<Map<String, dynamic>?>('atual', tipoConta, (
      response,
      sessao,
    ) {
      if (response.statusCode == 404) return null;
      _verificarStatus(response);
      return _validarMapa(
        _decodificar(response),
        sessao,
        tipoObrigatorio: tipoConta != null,
      );
    });
  }

  static Future<List<Map<String, dynamic>>> buscarHistorico({
    TipoContaAssinatura? tipoConta,
  }) {
    return _consultar<List<Map<String, dynamic>>>('historico', tipoConta, (
      response,
      sessao,
    ) {
      _verificarStatus(response);
      final dados = _decodificar(response);
      if (dados is! List) {
        throw const FormatException('Formato de histórico inválido.');
      }
      return dados.map<Map<String, dynamic>>((item) {
        return _validarMapa(item, sessao, tipoObrigatorio: tipoConta != null);
      }).toList();
    });
  }

  static Future<Map<String, dynamic>> buscarConsumo({
    TipoContaAssinatura? tipoConta,
  }) {
    return _consultar<Map<String, dynamic>>('consumo', tipoConta, (
      response,
      sessao,
    ) {
      _verificarStatus(response);
      return _validarMapa(
        _decodificar(response),
        sessao,
        tipoObrigatorio: tipoConta != null,
      );
    });
  }

  static Future<Map<String, dynamic>> iniciarTesteEssencial() async {
    if (_ativandoTeste) {
      throw const AssinaturaException(
        'Já existe uma solicitação de ativação em andamento. Aguarde a confirmação.',
        statusCode: 409,
      );
    }
    _ativandoTeste = true;
    var solicitacaoIniciada = false;
    try {
      const tipo = TipoContaAssinatura.empresa;
      final sessao = await _obterSessao(tipoConta: tipo);
      solicitacaoIniciada = true;
      final response = await _requisitar('teste-essencial', sessao, post: true);
      await _conferirSessao(sessao, tipo);
      _verificarStatus(response, post: true);
      final dados = _validarMapa(
        _decodificar(response),
        sessao,
        tipoObrigatorio: true,
      );
      return dados;
    } on AssinaturaException catch (e) {
      if (solicitacaoIniciada &&
          e.statusCode == null &&
          !e.mensagem.contains('Consulte sua assinatura')) {
        throw AssinaturaException(
          '${e.mensagem} Consulte sua assinatura antes de tentar novamente.',
        );
      }
      rethrow;
    } on ApiException catch (e) {
      throw AssinaturaException(e.mensagem, statusCode: e.statusCode);
    } catch (e) {
      throw AssinaturaException(
        solicitacaoIniciada
            ? 'Não foi possível confirmar a ativação. Consulte sua assinatura antes de tentar novamente.'
            : ApiService.mensagemErro(
                e,
                mensagemPadrao: 'Não foi possível iniciar o teste gratuito.',
              ),
      );
    } finally {
      _ativandoTeste = false;
    }
  }
}
