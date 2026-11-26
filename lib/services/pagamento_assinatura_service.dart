import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'empresa_service.dart';

enum TipoContaPagamento { empresa, entregador }

class PagamentoAssinaturaException extends ApiException {
  const PagamentoAssinaturaException(super.mensagem, {super.statusCode});
}

class _SessaoPagamento {
  final TipoContaPagamento tipoConta;
  final String token;
  final String email;

  const _SessaoPagamento(this.tipoConta, this.token, this.email);

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };

  String get tipoEsperado =>
      tipoConta == TipoContaPagamento.empresa ? 'EMPRESA' : 'ENTREGADOR';
}

class PagamentoAssinaturaService {
  static const _tempoLimite = Duration(seconds: 30);
  static final _operacoesEmAndamento = <TipoContaPagamento>{};

  static Uri get _urlBase =>
      Uri.parse('${ApiConfig.baseUrl}/pagamentos/assinaturas');

  static Future<String?> _obterToken(TipoContaPagamento tipoConta) async {
    final token = switch (tipoConta) {
      TipoContaPagamento.empresa => await EmpresaService.obterTokenEmpresa(),
      TipoContaPagamento.entregador => await AuthService.obterToken(),
    };
    final valor = token?.trim();
    return valor == null || valor.isEmpty ? null : valor;
  }

  static Future<String?> _obterEmail(TipoContaPagamento tipoConta) {
    return switch (tipoConta) {
      TipoContaPagamento.empresa => EmpresaService.empresaLogada(),
      TipoContaPagamento.entregador => AuthService.usuarioLogado(),
    };
  }

  static Future<_SessaoPagamento> _obterSessao(
    TipoContaPagamento tipoConta,
  ) async {
    try {
      final token = await _obterToken(tipoConta);
      final email = await _obterEmail(tipoConta);
      if (token == null || email == null || email.trim().isEmpty) {
        throw PagamentoAssinaturaException(
          tipoConta == TipoContaPagamento.empresa
              ? 'Sua sessão empresarial expirou ou não está disponível. Faça login novamente.'
              : 'Sua sessão de entregador expirou ou não está disponível. Faça login novamente.',
          statusCode: 401,
        );
      }
      if (await _obterToken(tipoConta) != token) {
        throw const PagamentoAssinaturaException(
          'Sua sessão foi alterada. Faça login novamente.',
          statusCode: 401,
        );
      }
      return _SessaoPagamento(tipoConta, token, email.trim().toLowerCase());
    } on PagamentoAssinaturaException {
      rethrow;
    } catch (_) {
      throw const PagamentoAssinaturaException(
        'Não foi possível verificar sua sessão. Confira seu acesso antes de continuar.',
      );
    }
  }

  static Future<void> _conferirSessao(_SessaoPagamento sessao) async {
    final atual = await _obterSessao(sessao.tipoConta);
    if (atual.token != sessao.token || atual.email != sessao.email) {
      throw const PagamentoAssinaturaException(
        'Sua sessão foi alterada. Atualize os dados da conta.',
        statusCode: 401,
      );
    }
  }

  static String _validarPlano(String plano) {
    final valor = plano.trim().toUpperCase();
    if (valor != 'ESSENCIAL' && valor != 'PROFISSIONAL') {
      throw const PagamentoAssinaturaException(
        'Selecione um plano pago válido.',
        statusCode: 400,
      );
    }
    return valor;
  }

  static void _validarChave(String chave) {
    if (chave.trim().isEmpty || RegExp(r'[\x00-\x1F\x7F]').hasMatch(chave)) {
      throw const PagamentoAssinaturaException(
        'A identificação da tentativa de pagamento é inválida. Consulte suas cobranças antes de continuar.',
        statusCode: 400,
      );
    }
  }

  static void _validarId(int id) {
    if (id <= 0) {
      throw const PagamentoAssinaturaException(
        'O identificador do pagamento ou da assinatura é inválido.',
        statusCode: 400,
      );
    }
  }

  static String _orientacao(bool pix) => pix
      ? 'Consulte suas cobranças ou recupere a tentativa com a mesma chave antes de gerar outra cobrança.'
      : 'Consulte suas assinaturas antes de repetir a operação.';

  static void _validarStatus(
    http.Response response, {
    required bool mutacao,
    required bool pix,
  }) {
    final status = response.statusCode;
    if (status == 200 || status == 201) return;

    final erro = ApiService.erroHttp(
      status,
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    var mensagem = erro.mensagem;
    if (status == 502) {
      mensagem = 'O Mercado Pago não conseguiu confirmar a operação.';
    } else if (mensagem == ApiService.erroHttp(status, '').mensagem) {
      mensagem = switch (status) {
        400 => 'Os dados enviados para o pagamento são inválidos.',
        404 => 'Pagamento ou assinatura não encontrado.',
        409 => 'A operação não pôde ser concluída devido a um conflito.',
        _ => mensagem,
      };
    }
    if (mutacao &&
        (status >= 500 ||
            status == 408 ||
            status == 409 ||
            status == 429 ||
            (status >= 200 && status < 400))) {
      mensagem = '$mensagem ${_orientacao(pix)}';
    }
    throw PagamentoAssinaturaException(mensagem, statusCode: status);
  }

  static Future<T> _executar<T>({
    required TipoContaPagamento tipoConta,
    required String caminho,
    required T Function(dynamic dados, _SessaoPagamento sessao) interpretar,
    required String mensagemConsulta,
    bool mutacao = false,
    bool pix = false,
    Map<String, dynamic>? corpo,
    Map<String, String>? headersExtras,
  }) async {
    if (mutacao && !_operacoesEmAndamento.add(tipoConta)) {
      throw const PagamentoAssinaturaException(
        'Já existe uma operação financeira em andamento. Confira seu resultado antes de iniciar outra.',
        statusCode: 409,
      );
    }

    http.Client? client;
    var enviada = false;
    try {
      final sessao = await _obterSessao(tipoConta);
      final request =
          http.Request(
              mutacao ? 'POST' : 'GET',
              Uri.parse('$_urlBase/$caminho'),
            )
            ..headers.addAll(sessao.headers)
            ..followRedirects = false;
      if (headersExtras != null) {
        request.headers.addAll(headersExtras);
      }
      if (corpo != null) {
        request.body = jsonEncode(corpo);
      }

      await _conferirSessao(sessao);
      final conexao = http.Client();
      client = conexao;
      enviada = true;
      final response = await conexao
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_tempoLimite);
      try {
        await _conferirSessao(sessao);
      } on PagamentoAssinaturaException catch (e) {
        throw PagamentoAssinaturaException(
          mutacao
              ? '${e.mensagem} O resultado da operação não pôde ser confirmado nesta sessão.'
              : e.mensagem,
          statusCode: e.statusCode,
        );
      }
      _validarStatus(response, mutacao: mutacao, pix: pix);
      final dados = jsonDecode(utf8.decode(response.bodyBytes));
      try {
        return interpretar(dados, sessao);
      } on PagamentoAssinaturaException catch (e) {
        throw PagamentoAssinaturaException(
          mutacao ? '${e.mensagem} ${_orientacao(pix)}' : e.mensagem,
          statusCode: e.statusCode,
        );
      }
    } on PagamentoAssinaturaException {
      rethrow;
    } on TimeoutException {
      throw PagamentoAssinaturaException(
        mutacao && enviada
            ? 'O servidor demorou para responder. A operação pode ter sido realizada. ${_orientacao(pix)}'
            : 'O servidor demorou para responder. $mensagemConsulta',
      );
    } on http.ClientException {
      throw PagamentoAssinaturaException(
        mutacao && enviada
            ? 'Falha de conexão. A operação pode ter sido realizada. ${_orientacao(pix)}'
            : 'Não foi possível conectar ao servidor. Verifique sua conexão. $mensagemConsulta',
      );
    } on FormatException {
      throw PagamentoAssinaturaException(
        mutacao && enviada
            ? 'O servidor retornou dados inválidos. O resultado não pôde ser confirmado. ${_orientacao(pix)}'
            : 'O servidor retornou dados inválidos. $mensagemConsulta',
      );
    } catch (e) {
      throw PagamentoAssinaturaException(
        mutacao && enviada
            ? 'Não foi possível confirmar o resultado da operação. ${_orientacao(pix)}'
            : ApiService.mensagemErro(e, mensagemPadrao: mensagemConsulta),
        statusCode: e is ApiException ? e.statusCode : null,
      );
    } finally {
      client?.close();
      if (mutacao) {
        _operacoesEmAndamento.remove(tipoConta);
      }
    }
  }

  static Map<String, dynamic> _validarRegistro(
    dynamic dados,
    _SessaoPagamento sessao, {
    required String campoId,
    int? idEsperado,
    String? planoEsperado,
  }) {
    if (dados is! Map<String, dynamic>) {
      throw const FormatException('Formato de resposta inválido.');
    }
    final id = dados[campoId];
    final tipo = dados['tipoConta'];
    final plano = dados['plano'];
    final status = dados['status'];
    final valor = dados['valor'];
    if (id is! int || id <= 0 || (idEsperado != null && id != idEsperado)) {
      throw const PagamentoAssinaturaException(
        'O servidor retornou um identificador incompatível com a operação.',
      );
    }
    if (tipo != null && tipo != sessao.tipoEsperado) {
      throw const PagamentoAssinaturaException(
        'O servidor retornou dados de um perfil diferente do solicitado.',
      );
    }
    if (status is! String ||
        status.trim().isEmpty ||
        (plano != null && plano != 'ESSENCIAL' && plano != 'PROFISSIONAL') ||
        (planoEsperado != null && plano != null && plano != planoEsperado) ||
        (valor != null && (valor is! num || !valor.isFinite || valor <= 0))) {
      throw const PagamentoAssinaturaException(
        'Não foi possível validar os dados do pagamento ou da assinatura.',
      );
    }
    return dados;
  }

  static Future<Map<String, dynamic>> criarPix({
    required String plano,
    required String chaveIdempotencia,
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    final planoValidado = _validarPlano(plano);
    _validarChave(chaveIdempotencia);
    return _executar(
      tipoConta: tipoConta,
      caminho: 'pix',
      mutacao: true,
      pix: true,
      mensagemConsulta: 'Não foi possível solicitar a cobrança Pix.',
      corpo: {'plano': planoValidado, 'chaveIdempotencia': chaveIdempotencia},
      interpretar: (dados, sessao) => _validarRegistro(
        dados,
        sessao,
        campoId: 'pagamentoId',
        planoEsperado: planoValidado,
      ),
    );
  }

  static Future<Map<String, dynamic>> consultarPix({
    required int pagamentoId,
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    _validarId(pagamentoId);
    return _executar(
      tipoConta: tipoConta,
      caminho: 'pix/$pagamentoId',
      pix: true,
      mensagemConsulta:
          'Não foi possível consultar o pagamento. Tente novamente.',
      interpretar: (dados, sessao) => _validarRegistro(
        dados,
        sessao,
        campoId: 'pagamentoId',
        idEsperado: pagamentoId,
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> listarPixPendentes({
    required TipoContaPagamento tipoConta,
  }) {
    return _executar(
      tipoConta: tipoConta,
      caminho: 'pix/pendentes',
      pix: true,
      mensagemConsulta:
          'Não foi possível listar as cobranças Pix. Consulte novamente antes de gerar outra cobrança.',
      interpretar: (dados, sessao) {
        if (dados is! List) {
          throw const FormatException('Formato de lista inválido.');
        }
        final pagamentos = <Map<String, dynamic>>[];
        final identificadores = <int>{};
        for (final dado in dados) {
          final item = _validarRegistro(dado, sessao, campoId: 'pagamentoId');
          final id = item['pagamentoId'] as int;
          final plano = item['plano'];
          final valor = item['valor'];
          final status = item['status'];
          if (!identificadores.add(id) ||
              item['tipoConta'] != sessao.tipoEsperado ||
              (plano != 'ESSENCIAL' && plano != 'PROFISSIONAL') ||
              valor is! num ||
              !valor.isFinite ||
              valor <= 0 ||
              (status != 'PENDENTE' && status != 'APROVADO') ||
              item['planoAtivado'] != false ||
              item['requerConciliacao'] != true) {
            throw const PagamentoAssinaturaException(
              'Não foi possível validar as cobranças Pix pendentes com segurança. Consulte novamente antes de gerar outra cobrança.',
            );
          }
          pagamentos.add(item);
        }
        return pagamentos;
      },
    );
  }

  static Future<Map<String, dynamic>> criarAssinaturaRecorrente({
    required String plano,
    required String chaveIdempotencia,
    required String emailPagador,
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    final planoValidado = _validarPlano(plano);
    _validarChave(chaveIdempotencia);
    final email = emailPagador.trim();
    if (email.isEmpty ||
        email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const PagamentoAssinaturaException(
        'Informe um e-mail válido para o responsável pelo pagamento.',
        statusCode: 400,
      );
    }
    return _executar(
      tipoConta: tipoConta,
      caminho: 'recorrentes',
      mutacao: true,
      mensagemConsulta: 'Não foi possível solicitar a assinatura recorrente.',
      headersExtras: {'X-Idempotency-Key': chaveIdempotencia},
      corpo: {'plano': planoValidado, 'emailPagador': email},
      interpretar: (dados, sessao) => _validarRegistro(
        dados,
        sessao,
        campoId: 'assinaturaId',
        planoEsperado: planoValidado,
      ),
    );
  }

  static Future<Map<String, dynamic>> consultarAssinaturaRecorrente({
    required int assinaturaId,
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    _validarId(assinaturaId);
    return _executar(
      tipoConta: tipoConta,
      caminho: 'recorrentes/$assinaturaId',
      mensagemConsulta:
          'Não foi possível consultar a assinatura. Tente novamente.',
      interpretar: (dados, sessao) => _validarRegistro(
        dados,
        sessao,
        campoId: 'assinaturaId',
        idEsperado: assinaturaId,
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> listarAssinaturasRecorrentes({
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) {
    return _executar(
      tipoConta: tipoConta,
      caminho: 'recorrentes',
      mensagemConsulta:
          'Não foi possível listar as assinaturas. Consulte novamente.',
      interpretar: (dados, sessao) {
        if (dados is! List) {
          throw const FormatException('Formato de lista inválido.');
        }
        final assinaturas = <Map<String, dynamic>>[];
        final identificadores = <int>{};
        for (final dado in dados) {
          final item = _validarRegistro(dado, sessao, campoId: 'assinaturaId');
          if (!identificadores.add(item['assinaturaId'] as int)) {
            throw const PagamentoAssinaturaException(
              'O servidor retornou assinaturas duplicadas. Atualize os dados antes de continuar.',
            );
          }
          assinaturas.add(item);
        }
        return assinaturas;
      },
    );
  }

  static Future<Map<String, dynamic>> cancelarAssinaturaRecorrente({
    required int assinaturaId,
    TipoContaPagamento tipoConta = TipoContaPagamento.empresa,
  }) async {
    _validarId(assinaturaId);
    return _executar(
      tipoConta: tipoConta,
      caminho: 'recorrentes/$assinaturaId/cancelar',
      mutacao: true,
      mensagemConsulta: 'Não foi possível solicitar o cancelamento.',
      interpretar: (dados, sessao) => _validarRegistro(
        dados,
        sessao,
        campoId: 'assinaturaId',
        idEsperado: assinaturaId,
      ),
    );
  }
}
