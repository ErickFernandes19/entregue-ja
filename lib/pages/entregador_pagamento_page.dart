import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/assinatura_service.dart';
import '../services/auth_service.dart';
import '../services/pagamento_assinatura_service.dart';

class EntregadorPagamentoPage extends StatefulWidget {
  final String plano;
  final String precoMensal;

  const EntregadorPagamentoPage({
    super.key,
    required this.plano,
    required this.precoMensal,
  });

  @override
  State<EntregadorPagamentoPage> createState() =>
      _EntregadorPagamentoPageState();
}

enum _FormaPagamentoEntregador { pix, cartao }

class _EntregadorPagamentoPageState extends State<EntregadorPagamentoPage> {
  static const _tipo = TipoContaPagamento.entregador;
  static const _planos = {'ESSENCIAL': 'R\$ 9,90', 'PROFISSIONAL': 'R\$ 19,90'};
  static const _statusPix = {
    'PENDENTE',
    'APROVADO',
    'RECUSADO',
    'CANCELADO',
    'REEMBOLSADO',
  };
  static const _statusRecorrente = {
    'PENDENTE',
    'AUTORIZADA',
    'PAUSADA',
    'CANCELADA',
    'ENCERRADA',
  };
  static const _estadosCriacao = {
    'PREPARADA',
    'ENVIANDO',
    'INCERTA',
    'CONFIRMADA',
  };

  final _emailController = TextEditingController();
  _FormaPagamentoEntregador _forma = _FormaPagamentoEntregador.pix;
  bool _ocupado = false;
  bool _pronto = false;
  String? _erro;
  String? _token;
  String? _chaveLocal;
  Map<String, dynamic>? _tentativa;
  Map<String, dynamic>? _pix;
  List<Map<String, dynamic>> _pixPendentes = [];
  bool _pixVerificado = false;
  Map<String, dynamic>? _recorrente;
  Map<String, dynamic>? _planoAtivo;
  bool _multiplasRecorrentes = false;

  String get _planoApi => widget.plano.trim().toUpperCase();
  String get _planoExibido =>
      (_pix?['plano'] as String?) ??
      (_tentativa?['plano'] as String?) ??
      (_recorrenteAberta ? (_recorrente?['plano'] as String?) : null) ??
      _planoApi;
  bool get _pixPendente => _pix?['status'] == 'PENDENTE';
  bool get _pixAtivado =>
      _pix?['status'] == 'APROVADO' && _pix?['planoAtivado'] == true;
  bool get _pixFinalizado =>
      _pixAtivado ||
      const {'RECUSADO', 'CANCELADO', 'REEMBOLSADO'}.contains(_pix?['status']);
  bool get _recorrenteAberta =>
      _recorrente != null &&
      (_recorrente?['estadoCriacao'] != 'CONFIRMADA' ||
          const {
            'PENDENTE',
            'AUTORIZADA',
            'PAUSADA',
          }.contains(_recorrente?['status']));
  bool get _contratacaoBloqueada =>
      _planoAtivo?['status'] == 'ATIVA' &&
      (_planoAtivo?['planoAgendado'] != null ||
          _planoAtivo?['renovacaoAutomatica'] == true ||
          (_planoAtivo?['plano'] != 'GRATUITO' &&
              _planoAtivo?['plano'] != _planoApi));
  bool get _podeCriar =>
      !_contratacaoBloqueada &&
      _erro == null &&
      _pronto &&
      !_ocupado &&
      !_multiplasRecorrentes &&
      _pixVerificado &&
      _pixPendentes.isEmpty &&
      _tentativa == null &&
      !_recorrenteAberta &&
      _pix == null &&
      _planos.containsKey(_planoApi);

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  bool _emailValido(String email) =>
      email.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  void _invalidarSessao() {
    if (!mounted) return;
    setState(() {
      _pronto = false;
      _pix = null;
      _pixPendentes = [];
      _pixVerificado = false;
      _recorrente = null;
      _planoAtivo = null;
      _tentativa = null;
      _multiplasRecorrentes = false;
      _emailController.clear();
    });
  }

  Future<void> _validarSessao() async {
    if (!mounted) {
      throw const PagamentoAssinaturaException('A tela foi encerrada.');
    }
    final email = await AuthService.usuarioLogado();
    final tokenAtual = await AuthService.obterToken();
    if (!mounted || email == null || _token == null || tokenAtual != _token) {
      _invalidarSessao();
      throw const PagamentoAssinaturaException(
        'Sua sessão expirou ou mudou. Volte aos planos e faça login novamente.',
        statusCode: 401,
      );
    }
  }

  void _tratarFalha(Object e) {
    if (!mounted) return;
    if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
      _invalidarSessao();
    }
    setState(() {
      _erro = _mensagem(e);
      _pixVerificado = false;
    });
  }

  Future<void> _inicializar() async {
    if (!mounted || _ocupado) return;
    setState(() {
      _ocupado = true;
      _pronto = false;
      _pixVerificado = false;
      _erro = null;
    });
    try {
      final token = await AuthService.obterToken();
      if (token == null || await AuthService.usuarioLogado() == null) {
        throw const PagamentoAssinaturaException(
          'Faça login como entregador.',
          statusCode: 401,
        );
      }
      final partes = token.split('.');
      if (partes.length != 3) {
        throw const PagamentoAssinaturaException(
          'Sessão do entregador inválida. Faça login novamente.',
          statusCode: 401,
        );
      }
      final dynamic payload;
      try {
        payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
        );
      } on FormatException {
        throw const PagamentoAssinaturaException(
          'Sessão do entregador inválida. Faça login novamente.',
          statusCode: 401,
        );
      }
      if (payload is! Map<String, dynamic> || payload['tipo'] != 'ENTREGADOR') {
        throw const PagamentoAssinaturaException(
          'Sessão do entregador inválida.',
          statusCode: 401,
        );
      }
      final id = int.tryParse(payload['sub']?.toString() ?? '');
      final exp = payload['exp'];
      if (id == null ||
          id <= 0 ||
          exp is! num ||
          exp <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        throw const PagamentoAssinaturaException(
          'Sessão expirada. Faça login novamente.',
          statusCode: 401,
        );
      }
      if (_token != null && _token != token) {
        throw const PagamentoAssinaturaException(
          'A sessão mudou. Reabra esta tela.',
          statusCode: 401,
        );
      }
      if (!mounted) {
        return;
      }
      _token = token;
      _chaveLocal = 'entregueja_pagamento_tentativa_entregador_$id';
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await _validarSessao();
      final registro = prefs.getString(_chaveLocal!);
      if (registro != null) {
        final registroDecodificado = _decodificarTentativa(registro);
        if (registroDecodificado is! Map<String, dynamic>) {
          throw const PagamentoAssinaturaException(
            'Tentativa anterior inválida. Verifique a cobrança antes de continuar.',
          );
        }
        final dados = registroDecodificado;
        if (!_planos.containsKey(dados['plano']) ||
            !const {'pix', 'cartao'}.contains(dados['forma']) ||
            dados['chave'] is! String ||
            !RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ).hasMatch(dados['chave'] as String) ||
            (dados['id'] != null && _id(dados['id']) == null) ||
            (dados['forma'] == 'cartao' &&
                (dados['email'] is! String ||
                    !_emailValido(dados['email'] as String)))) {
          throw const PagamentoAssinaturaException(
            'Tentativa anterior inválida. Não gere outra cobrança antes de verificar a anterior.',
          );
        }
        _tentativa = dados;
        _forma = dados['forma'] == 'pix'
            ? _FormaPagamentoEntregador.pix
            : _FormaPagamentoEntregador.cartao;
        if (dados['forma'] == 'cartao') {
          _emailController.text = dados['email'] as String;
        }
      } else {
        _tentativa = null;
      }
      await _recuperarRecorrentes();
      await _recuperarPix();
      await _consultarPlano();
      if (mounted) {
        setState(() => _pronto = true);
      }
    } catch (e) {
      _tratarFalha(e);
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
      }
    }
  }

  String _mensagem(Object e) {
    return ApiService.mensagemErro(
      e,
      mensagemPadrao:
          'Não foi possível concluir a operação. Verifique sua sessão e a cobrança anterior antes de tentar novamente.',
    );
  }

  dynamic _decodificarTentativa(String registro) {
    try {
      return jsonDecode(registro);
    } on FormatException {
      throw const PagamentoAssinaturaException(
        'A tentativa salva está inválida. Consulte a cobrança anterior antes de continuar.',
      );
    }
  }

  int? _id(dynamic valor) => valor is int && valor > 0 ? valor : null;

  Future<void> _salvar(Map<String, dynamic> dados) async {
    await _validarSessao();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await _validarSessao();
    final existente = prefs.getString(_chaveLocal!);
    if (existente != null) {
      final anterior = _decodificarTentativa(existente);
      if (anterior is! Map || anterior['chave'] != dados['chave']) {
        throw const PagamentoAssinaturaException(
          'Existe outra tentativa salva. Reabra a tela antes de continuar.',
        );
      }
    } else if (_tentativa != null) {
      throw const PagamentoAssinaturaException(
        'A tentativa salva mudou. Reabra a tela.',
      );
    }
    if (!await prefs.setString(_chaveLocal!, jsonEncode(dados))) {
      throw const PagamentoAssinaturaException(
        'Não foi possível salvar a tentativa com segurança.',
      );
    }
    await _validarSessao();
    _tentativa = dados;
  }

  Future<void> _limparTentativa() async {
    final tentativa = _tentativa;
    if (tentativa == null) {
      return;
    }
    await _validarSessao();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await _validarSessao();
    final registro = prefs.getString(_chaveLocal!);
    if (registro != null) {
      final dados = _decodificarTentativa(registro);
      if (dados is! Map || dados['chave'] != tentativa['chave']) {
        throw const PagamentoAssinaturaException(
          'Outra tentativa está salva. Reabra a tela.',
        );
      }
      if (!await prefs.remove(_chaveLocal!)) {
        throw const PagamentoAssinaturaException(
          'Não foi possível atualizar a tentativa salva.',
        );
      }
    }
    await _validarSessao();
    _tentativa = null;
  }

  Future<void> _executar(Future<void> Function() acao) async {
    if (!mounted || _ocupado || !_pronto) {
      return;
    }
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await _validarSessao();
      await acao();
    } catch (e) {
      _tratarFalha(e);
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
      }
    }
  }

  Future<void> _consultarPlano() async {
    await _validarSessao();
    final dados = await AssinaturaService.buscarAtual(
      tipoConta: TipoContaAssinatura.entregador,
    );
    await _validarSessao();
    if (dados != null &&
        (!const {
              'GRATUITO',
              'ESSENCIAL',
              'PROFISSIONAL',
            }.contains(dados['plano']) ||
            !const {
              'ATIVA',
              'PENDENTE',
              'CANCELADA',
              'EXPIRADA',
            }.contains(dados['status']))) {
      throw const PagamentoAssinaturaException(
        'Não foi possível validar o plano atual. Consulte sua assinatura antes de continuar.',
      );
    }
    _planoAtivo = dados;
  }

  bool _aberta(Map<String, dynamic> dados) =>
      dados['estadoCriacao'] != 'CONFIRMADA' ||
      const {'PENDENTE', 'AUTORIZADA', 'PAUSADA'}.contains(dados['status']);

  void _validarRecorrente(Map<String, dynamic> dados, {int? esperado}) {
    final id = _id(dados['assinaturaId']);
    final plano = dados['plano'];
    final valor = dados['valorMensal'];
    final valorEsperado = plano == 'ESSENCIAL' ? 9.90 : 19.90;
    if (id == null ||
        (esperado != null && id != esperado) ||
        (dados['tipoConta'] != null && dados['tipoConta'] != 'ENTREGADOR') ||
        !_planos.containsKey(plano) ||
        valor is! num ||
        !valor.isFinite ||
        (valor - valorEsperado).abs() > 0.000001 ||
        !_statusRecorrente.contains(dados['status']) ||
        !_estadosCriacao.contains(dados['estadoCriacao'])) {
      throw const PagamentoAssinaturaException(
        'Dados da assinatura recorrente inválidos.',
      );
    }
  }

  Future<void> _recuperarRecorrentes() async {
    await _validarSessao();
    final lista = await PagamentoAssinaturaService.listarAssinaturasRecorrentes(
      tipoConta: _tipo,
    );
    await _validarSessao();
    final identificadores = <int>{};
    for (final dados in lista) {
      _validarRecorrente(dados);
      if (!identificadores.add(_id(dados['assinaturaId'])!)) {
        throw const PagamentoAssinaturaException(
          'A lista de assinaturas contém identificadores duplicados.',
        );
      }
    }
    final abertas = lista.where(_aberta).toList();
    final tentativa = _tentativa;
    final idSalvo = tentativa?['forma'] == 'cartao'
        ? _id(tentativa?['id'])
        : null;
    Map<String, dynamic>? selecionada;
    if (idSalvo != null) {
      for (final dados in lista) {
        if (dados['assinaturaId'] == idSalvo) {
          selecionada = dados;
          break;
        }
      }
    }
    if (idSalvo != null) {
      selecionada ??=
          await PagamentoAssinaturaService.consultarAssinaturaRecorrente(
            assinaturaId: idSalvo,
            tipoConta: _tipo,
          );
      await _validarSessao();
      _validarRecorrente(selecionada, esperado: idSalvo);
      if (selecionada['plano'] != tentativa?['plano']) {
        throw const PagamentoAssinaturaException(
          'A assinatura não corresponde ao plano da tentativa salva.',
        );
      }
      if (_aberta(selecionada) &&
          !abertas.any((item) => item['assinaturaId'] == idSalvo)) {
        abertas.add(selecionada);
      }
    }
    _multiplasRecorrentes = abertas.length > 1;
    selecionada ??= abertas.isEmpty ? null : abertas.first;
    _recorrente = selecionada;
    if (selecionada != null && tentativa?['forma'] != 'pix') {
      _forma = _FormaPagamentoEntregador.cartao;
    }
    if (selecionada != null &&
        idSalvo != null &&
        selecionada['assinaturaId'] == idSalvo &&
        !_aberta(selecionada)) {
      await _limparTentativa();
      if (abertas.isNotEmpty) {
        _recorrente = abertas.first;
      }
    }
  }

  void _validarPix(Map<String, dynamic> dados, {int? esperado}) {
    final id = _id(dados['pagamentoId']);
    final valor = dados['valor'];
    final plano = dados['plano'];
    final status = dados['status'];
    final externo = dados['mercadoPagoPagamentoId'];
    final valorEsperado = plano == 'ESSENCIAL' ? 9.90 : 19.90;
    if (id == null ||
        (esperado != null && id != esperado) ||
        dados['tipoConta'] != 'ENTREGADOR' ||
        !_planos.containsKey(plano) ||
        valor is! num ||
        !valor.isFinite ||
        (valor - valorEsperado).abs() > 0.000001 ||
        !_statusPix.contains(status) ||
        dados['planoAtivado'] is! bool ||
        dados['requerConciliacao'] is! bool ||
        (dados['requerConciliacao'] !=
            (status == 'PENDENTE' ||
                (status == 'APROVADO' && dados['planoAtivado'] == false))) ||
        (externo != null &&
            (externo is! String ||
                (externo.trim().isNotEmpty &&
                    !RegExp(r'^[0-9]+$').hasMatch(externo))))) {
      throw const PagamentoAssinaturaException(
        'O servidor retornou dados inconsistentes do Pix.',
      );
    }
  }

  Future<void> _atualizarPix(
    Map<String, dynamic> dados, {
    int? esperado,
    bool vincularTentativa = false,
  }) async {
    _validarPix(dados, esperado: esperado);
    final id = _id(dados['pagamentoId'])!;
    final tentativa = _tentativa;
    final corresponde =
        tentativa?['forma'] == 'pix' &&
        (tentativa?['id'] == id ||
            (vincularTentativa && tentativa?['id'] == null));
    if (vincularTentativa && !corresponde) {
      throw const PagamentoAssinaturaException(
        'O pagamento não corresponde à tentativa salva.',
      );
    }
    if (corresponde && tentativa != null) {
      if (dados['plano'] != tentativa['plano']) {
        throw const PagamentoAssinaturaException(
          'O plano retornado não corresponde à tentativa salva.',
        );
      }
      await _salvar({...tentativa, 'id': id});
    }
    _pix = dados;
    _pixPendentes = [
      for (final item in _pixPendentes)
        if (item['pagamentoId'] != id) item,
      if (dados['requerConciliacao'] == true) dados,
    ];
    if (corresponde && _pixFinalizado) {
      await _limparTentativa();
    }
  }

  Future<void> _consultarPixInterno({int? pagamentoId}) async {
    final id =
        pagamentoId ??
        _id(_pix?['pagamentoId']) ??
        (_tentativa?['forma'] == 'pix' ? _id(_tentativa?['id']) : null);
    if (id == null) {
      return;
    }
    await _validarSessao();
    final dados = await PagamentoAssinaturaService.consultarPix(
      pagamentoId: id,
      tipoConta: _tipo,
    );
    await _validarSessao();
    await _atualizarPix(dados, esperado: id);
  }

  Future<void> _recuperarPix({bool consultar = true}) async {
    _pixVerificado = false;
    await _validarSessao();
    final lista = await PagamentoAssinaturaService.listarPixPendentes(
      tipoConta: _tipo,
    );
    await _validarSessao();
    for (final item in lista) {
      _validarPix(item);
    }
    _pixPendentes = lista;
    _pixVerificado = true;
    final idLocal = _tentativa?['forma'] == 'pix'
        ? _id(_tentativa?['id'])
        : null;
    final idAtual = _id(_pix?['pagamentoId']);
    Map<String, dynamic>? selecionado;
    for (final item in lista) {
      if (item['pagamentoId'] == idAtual) {
        selecionado = item;
        break;
      }
    }
    if (selecionado == null && idLocal != null) {
      for (final item in lista) {
        if (item['pagamentoId'] == idLocal) {
          selecionado = item;
          break;
        }
      }
    }
    if (lista.isNotEmpty) {
      selecionado ??= lista.first;
    }
    if (selecionado != null) {
      _pix = selecionado;
      _forma = _FormaPagamentoEntregador.pix;
    }
    if (!consultar) {
      return;
    }
    if (idLocal != null &&
        !lista.any((item) => item['pagamentoId'] == idLocal)) {
      await _consultarPixInterno(pagamentoId: idLocal);
    }
    if (selecionado != null) {
      _pix = selecionado;
      await _consultarPixInterno(pagamentoId: _id(selecionado['pagamentoId'])!);
    } else if (_pix != null &&
        !_pixFinalizado &&
        idAtual != null &&
        idAtual != idLocal) {
      await _consultarPixInterno(pagamentoId: idAtual);
    }
  }

  Future<void> _selecionarPix(int id) => _executar(() async {
    for (final item in _pixPendentes) {
      if (item['pagamentoId'] == id) {
        _pix = item;
        break;
      }
    }
    await _consultarPixInterno(pagamentoId: id);
    await _consultarPlano();
  });

  Future<void> _criarOuRetomarPix() => _executar(() async {
    await _recuperarRecorrentes();
    await _recuperarPix(consultar: false);
    await _consultarPlano();
    if (_tentativa == null) {
      if (_pixPendentes.isNotEmpty ||
          _recorrenteAberta ||
          _multiplasRecorrentes ||
          _contratacaoBloqueada ||
          !_planos.containsKey(_planoApi) ||
          _pix != null) {
        throw const PagamentoAssinaturaException(
          'Existe uma cobrança, assinatura ou plano que impede uma nova contratação. Consulte os dados antes de continuar.',
        );
      }
      await _salvar({'forma': 'pix', 'plano': _planoApi, 'chave': _uuid()});
    }
    final tentativa = _tentativa!;
    if (tentativa['forma'] != 'pix') {
      throw const PagamentoAssinaturaException(
        'Existe uma tentativa por cartão. Consulte-a antes de gerar um Pix.',
      );
    }
    if (_id(tentativa['id']) != null) {
      await _consultarPixInterno(pagamentoId: _id(tentativa['id'])!);
      await _consultarPlano();
      return;
    }
    if (_pixPendentes.isNotEmpty ||
        _recorrenteAberta ||
        _multiplasRecorrentes) {
      throw const PagamentoAssinaturaException(
        'Consulte as cobranças em aberto antes de retomar a tentativa salva.',
      );
    }
    await _validarSessao();
    final dados = await PagamentoAssinaturaService.criarPix(
      plano: tentativa['plano'] as String,
      chaveIdempotencia: tentativa['chave'] as String,
      tipoConta: _tipo,
    );
    await _validarSessao();
    await _atualizarPix(dados, vincularTentativa: true);
    await _consultarPlano();
  });

  Future<void> _criarOuRetomarCartao() => _executar(() async {
    await _recuperarRecorrentes();
    await _recuperarPix(consultar: false);
    await _consultarPlano();
    if (_multiplasRecorrentes || _pixPendentes.isNotEmpty || _pix != null) {
      throw const PagamentoAssinaturaException(
        'Consulte as cobranças ou assinaturas existentes antes de continuar.',
      );
    }
    if (_tentativa == null) {
      if (_contratacaoBloqueada ||
          _recorrenteAberta ||
          !_planos.containsKey(_planoApi)) {
        throw const PagamentoAssinaturaException(
          'O plano atual ou uma assinatura existente impede uma nova contratação.',
        );
      }
      final email = _emailController.text.trim();
      if (!_emailValido(email)) {
        throw const PagamentoAssinaturaException(
          'Informe um e-mail válido para o pagamento.',
        );
      }
      await _salvar({
        'forma': 'cartao',
        'plano': _planoApi,
        'chave': _uuid(),
        'email': email,
      });
    }
    final tentativa = _tentativa!;
    if (tentativa['forma'] != 'cartao') {
      throw const PagamentoAssinaturaException(
        'Existe uma tentativa por Pix. Consulte-a antes de contratar por cartão.',
      );
    }
    if (_id(tentativa['id']) != null) {
      await _consultarRecorrenteInterno(_id(tentativa['id'])!);
      return;
    }
    if (_recorrenteAberta && _recorrente?['plano'] != tentativa['plano']) {
      throw const PagamentoAssinaturaException(
        'Existe uma assinatura de outro plano em andamento. Consulte o gerenciamento antes de retomar a tentativa.',
      );
    }
    await _validarSessao();
    final dados = await PagamentoAssinaturaService.criarAssinaturaRecorrente(
      plano: tentativa['plano'] as String,
      chaveIdempotencia: tentativa['chave'] as String,
      emailPagador: tentativa['email'] as String,
      tipoConta: _tipo,
    );
    await _validarSessao();
    _validarRecorrente(dados);
    if (dados['plano'] != tentativa['plano']) {
      throw const PagamentoAssinaturaException(
        'O plano retornado não corresponde à tentativa.',
      );
    }
    await _salvar({...tentativa, 'id': dados['assinaturaId']});
    _recorrente = dados;
    if (!_aberta(dados)) {
      await _limparTentativa();
    }
  });

  Future<void> _consultarRecorrenteInterno(int id) async {
    await _validarSessao();
    final dados =
        await PagamentoAssinaturaService.consultarAssinaturaRecorrente(
          assinaturaId: id,
          tipoConta: _tipo,
        );
    await _validarSessao();
    _validarRecorrente(dados, esperado: id);
    if (_tentativa?['forma'] == 'cartao' &&
        _tentativa?['id'] == id &&
        _tentativa?['plano'] != dados['plano']) {
      throw const PagamentoAssinaturaException(
        'A assinatura consultada não corresponde à tentativa salva.',
      );
    }
    _recorrente = dados;
    if (!_aberta(dados) &&
        _tentativa?['forma'] == 'cartao' &&
        _tentativa?['id'] == id) {
      await _limparTentativa();
    }
  }

  Future<void> _atualizar() => _executar(() async {
    await _recuperarRecorrentes();
    await _recuperarPix();
    final id = _id(_recorrente?['assinaturaId']);
    if (id != null) {
      await _consultarRecorrenteInterno(id);
    }
    await _consultarPlano();
  });

  Future<void> _abrirMercadoPago() => _executar(() async {
    final id = _id(_recorrente?['assinaturaId']);
    await _recuperarRecorrentes();
    await _recuperarPix(consultar: false);
    await _consultarPlano();
    if (id != null && _recorrente?['assinaturaId'] == id) {
      await _consultarRecorrenteInterno(id);
    }
    if (id == null ||
        _recorrente?['assinaturaId'] != id ||
        _pixPendentes.isNotEmpty ||
        _multiplasRecorrentes ||
        (_tentativa != null &&
            (_tentativa?['forma'] != 'cartao' ||
                _tentativa?['id'] != _recorrente?['assinaturaId'])) ||
        _recorrente?['status'] != 'PENDENTE' ||
        _recorrente?['estadoCriacao'] != 'CONFIRMADA') {
      throw const PagamentoAssinaturaException(
        'Não foi possível confirmar a autorização desta assinatura. Atualize os dados antes de continuar.',
      );
    }
    final uri = Uri.tryParse(_recorrente?['urlAutorizacao']?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !const [
          'mercadopago.com',
          'mercadopago.com.br',
        ].any((host) => uri.host == host || uri.host.endsWith('.$host'))) {
      throw const PagamentoAssinaturaException(
        'O endereço de autorização do Mercado Pago é inválido.',
      );
    }
    await _validarSessao();
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const PagamentoAssinaturaException(
        'Não foi possível abrir o Mercado Pago.',
      );
    }
  });

  Future<void> _copiarPix() => _executar(() async {
    final id = _id(_pix?['pagamentoId']);
    await _recuperarRecorrentes();
    await _recuperarPix();
    await _consultarPlano();
    final codigo = _pix?['pixCopiaECola'];
    if (id == null ||
        _pix?['pagamentoId'] != id ||
        !_pixPendente ||
        !_pixVerificado ||
        _pixPendentes.length != 1 ||
        _pixPendentes.first['pagamentoId'] != id ||
        _recorrenteAberta ||
        _multiplasRecorrentes ||
        codigo is! String ||
        codigo.trim().isEmpty) {
      throw const PagamentoAssinaturaException(
        'Não foi possível confirmar o código Pix desta cobrança. Consulte o pagamento antes de continuar.',
      );
    }
    await _validarSessao();
    await Clipboard.setData(ClipboardData(text: codigo));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Código Pix copiado.')));
    }
  });

  String _rotulo(String? plano) => switch (plano) {
    'ESSENCIAL' => 'Essencial',
    'PROFISSIONAL' => 'Profissional',
    'GRATUITO' => 'Gratuito',
    _ => 'Não informado',
  };

  Widget _botao(String texto, VoidCallback? acao, IconData icone) =>
      FilledButton.icon(
        onPressed: acao,
        icon: Icon(icone),
        label: Text(texto),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );

  Widget _painelPix(ThemeData theme) {
    final codigo = _pix?['pixCopiaECola'];
    final status = _pix?['status'];
    final mensagem = !_pixVerificado && !_ocupado
        ? 'Não foi possível confirmar o estado atual da cobrança. Consulte novamente antes de pagar.'
        : switch (status) {
            'PENDENTE' =>
              (_pix?['mercadoPagoPagamentoId']?.toString().trim().isEmpty ??
                      true)
                  ? 'A cobrança ainda não foi identificada no Mercado Pago. Consulte novamente; não gere outro Pix.'
                  : 'Aguardando pagamento. Confira o valor e a validade no seu banco.',
            'APROVADO' =>
              _pixAtivado
                  ? 'Pagamento aprovado e plano ativado para esta cobrança.'
                  : 'Pagamento aprovado. Aguardando confirmação da ativação.',
            'RECUSADO' => 'Pagamento recusado.',
            'CANCELADO' => 'Pagamento cancelado.',
            'REEMBOLSADO' => 'Pagamento reembolsado.',
            _ =>
              'Nenhum pagamento confirmado. Verifique a tentativa salva antes de contratar novamente.',
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pagamento Pix', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(mensagem),
            if (_pix != null) ...[
              const SizedBox(height: 8),
              Text(
                'Cobrança #${_pix?['pagamentoId']} — Plano ${_rotulo(_pix?['plano'] as String?)}',
              ),
            ],
            if (_pixPendentes.length > 1 ||
                (_pixPendentes.isNotEmpty &&
                    !_pixPendentes.any(
                      (item) => item['pagamentoId'] == _pix?['pagamentoId'],
                    ))) ...[
              const SizedBox(height: 12),
              Text(
                _pixPendentes.length > 1
                    ? 'Há mais de uma cobrança em aberto. Consulte cada uma antes de realizar qualquer pagamento.'
                    : 'Há outra cobrança em aberto. Consulte-a antes de continuar.',
              ),
              for (final item in _pixPendentes)
                OutlinedButton(
                  onPressed: _pronto && !_ocupado
                      ? () => _selecionarPix(_id(item['pagamentoId'])!)
                      : null,
                  child: Text(
                    'Consultar #${item['pagamentoId']} — ${_rotulo(item['plano'] as String?)}',
                  ),
                ),
            ],
            if (_pixPendente &&
                _pixVerificado &&
                _pixPendentes.length == 1 &&
                _pixPendentes.first['pagamentoId'] == _pix?['pagamentoId'] &&
                !_recorrenteAberta &&
                !_multiplasRecorrentes &&
                _pronto &&
                !_ocupado &&
                _erro == null &&
                codigo is String &&
                codigo.isNotEmpty) ...[
              const SizedBox(height: 16),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: codigo,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(codigo, maxLines: 4),
              const SizedBox(height: 12),
              _botao(
                'Copiar código Pix',
                _ocupado ? null : _copiarPix,
                Icons.copy,
              ),
            ],
            const SizedBox(height: 12),
            if (_pix != null ||
                _id(_tentativa?['id']) != null ||
                _pixPendentes.isNotEmpty)
              _botao(
                'Consultar pagamento',
                _pronto && !_ocupado ? _atualizar : null,
                Icons.refresh,
              ),
            if (_tentativa?['forma'] == 'pix' &&
                _id(_tentativa?['id']) == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Existe uma tentativa salva neste dispositivo. Retome somente se desejar concluir essa contratação. Se ela ainda não foi registrada no servidor, a solicitação poderá gerar o Pix original.',
              ),
              _botao(
                'Retomar tentativa salva',
                _pronto &&
                        !_ocupado &&
                        _pixVerificado &&
                        _erro == null &&
                        _pixPendentes.isEmpty &&
                        !_recorrenteAberta &&
                        !_multiplasRecorrentes
                    ? _criarOuRetomarPix
                    : null,
                Icons.refresh,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _painelCartao(ThemeData theme) {
    final status = _recorrente?['status'];
    final criacao = _recorrente?['estadoCriacao'];
    final externa = _recorrente?['mercadoPagoAssinaturaId'];
    final ativada =
        status == 'AUTORIZADA' &&
        externa is String &&
        externa.isNotEmpty &&
        _planoAtivo?['status'] == 'ATIVA' &&
        _planoAtivo?['plano'] == _recorrente?['plano'] &&
        _planoAtivo?['mercadoPagoAssinaturaId'] == externa;
    final mensagem = !_pixVerificado && !_ocupado
        ? 'Não foi possível confirmar o estado atual da assinatura. Atualize os dados antes de continuar.'
        : criacao != null && criacao != 'CONFIRMADA'
        ? 'A criação da assinatura ainda não foi confirmada. Não inicie outra contratação.'
        : switch (status) {
            'PENDENTE' =>
              'Autorize a assinatura no ambiente seguro do Mercado Pago.',
            'AUTORIZADA' =>
              ativada
                  ? 'Assinatura autorizada e plano ativo.'
                  : 'Assinatura autorizada. Aguardando confirmação do pagamento e ativação do plano.',
            'PAUSADA' =>
              'Assinatura pausada. Consulte o status antes de contratar outro plano.',
            'CANCELADA' => 'Assinatura recorrente cancelada.',
            'ENCERRADA' => 'Assinatura recorrente encerrada.',
            _ =>
              'Existe uma tentativa de contratação salva. Verifique ou retome a mesma solicitação.',
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Assinatura por cartão', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_recorrente != null)
              Text('Plano ${_rotulo(_recorrente?['plano'] as String?)}'),
            Text(mensagem),
            const SizedBox(height: 12),
            if (status == 'PENDENTE' &&
                criacao == 'CONFIRMADA' &&
                !_multiplasRecorrentes &&
                _pixVerificado &&
                _pixPendentes.isEmpty &&
                (_tentativa == null ||
                    (_tentativa?['forma'] == 'cartao' &&
                        _tentativa?['id'] ==
                            _recorrente?['assinaturaId']))) ...[
              _botao(
                'Autorizar no Mercado Pago',
                _pronto && !_ocupado && _erro == null
                    ? _abrirMercadoPago
                    : null,
                Icons.open_in_new,
              ),
              const SizedBox(height: 8),
            ],
            if (_tentativa?['forma'] == 'cartao' &&
                _id(_tentativa?['id']) == null) ...[
              OutlinedButton.icon(
                onPressed:
                    _pronto &&
                        !_ocupado &&
                        !_multiplasRecorrentes &&
                        _pixVerificado &&
                        _erro == null &&
                        _pixPendentes.isEmpty &&
                        _pix == null
                    ? _criarOuRetomarCartao
                    : null,
                icon: const Icon(Icons.sync),
                label: const Text('Retomar tentativa anterior'),
              ),
              const SizedBox(height: 8),
            ],
            _botao(
              'Atualizar assinatura e plano',
              _pronto && !_ocupado ? _atualizar : null,
              Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recuperacao =
        _tentativa != null ||
        _recorrenteAberta ||
        _pix != null ||
        _pixPendentes.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Pagamento da assinatura')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Resumo da assinatura', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plano ${_rotulo(_planoExibido)}',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _planos[_planoExibido] ?? '—',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: Text('/mês'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Plano para entregas independentes.'),
                        if (_planoExibido != _planoApi)
                          const Text(
                            'Exibindo uma contratação anterior. Resolva-a antes de contratar outro plano.',
                          ),
                        if (_planoAtivo != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Plano atual informado pelo servidor: ${_rotulo(_planoAtivo?['plano'] as String?)}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_ocupado) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_erro != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _erro!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if ((!_pronto || !_pixVerificado) && !_ocupado) ...[
                  const SizedBox(height: 12),
                  _botao(
                    'Verificar pagamentos anteriores',
                    _inicializar,
                    Icons.refresh,
                  ),
                ],
                if (_multiplasRecorrentes) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Há mais de uma assinatura em aberto. Verifique o gerenciamento de assinaturas antes de continuar.',
                  ),
                ],
                const SizedBox(height: 24),
                if (!recuperacao && _contratacaoBloqueada)
                  const Text(
                    'Existe um plano ativo, renovação automática ou troca agendada que impede esta contratação. Consulte sua assinatura antes de continuar.',
                  ),
                if (!recuperacao && !_multiplasRecorrentes) ...[
                  Text('Forma de pagamento', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: RadioGroup<_FormaPagamentoEntregador>(
                      groupValue: _forma,
                      onChanged: (value) {
                        if (value != null && _podeCriar) {
                          setState(() => _forma = value);
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile<_FormaPagamentoEntregador>(
                            enabled: _podeCriar,
                            value: _FormaPagamentoEntregador.pix,
                            title: const Text('Pix'),
                            subtitle: const Text(
                              'Pagamento por QR Code ou código copia e cola',
                            ),
                            secondary: const Icon(Icons.qr_code_2),
                          ),
                          const Divider(height: 1),
                          RadioListTile<_FormaPagamentoEntregador>(
                            enabled: _podeCriar,
                            value: _FormaPagamentoEntregador.cartao,
                            title: const Text('Cartão de crédito'),
                            subtitle: const Text(
                              'Assinatura mensal recorrente',
                            ),
                            secondary: const Icon(Icons.credit_card),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_forma == _FormaPagamentoEntregador.cartao) ...[
                    TextField(
                      controller: _emailController,
                      enabled: _podeCriar,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail do pagador',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Você autorizará a cobrança recorrente no Mercado Pago. Não informe dados do cartão nesta tela.',
                    ),
                    const SizedBox(height: 12),
                    _botao(
                      'Criar assinatura recorrente',
                      _podeCriar ? _criarOuRetomarCartao : null,
                      Icons.credit_card,
                    ),
                  ] else ...[
                    const Text(
                      'Pagamento único via Pix, sem renovação automática.',
                    ),
                    const SizedBox(height: 12),
                    _botao(
                      'Gerar Pix',
                      _podeCriar ? _criarOuRetomarPix : null,
                      Icons.qr_code_2,
                    ),
                  ],
                ],
                if (_pix != null ||
                    _pixPendentes.isNotEmpty ||
                    _tentativa?['forma'] == 'pix')
                  _painelPix(theme),
                if (_recorrente != null || _tentativa?['forma'] == 'cartao')
                  _painelCartao(theme),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _ocupado
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Voltar aos planos'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Os pagamentos são processados pelo Mercado Pago. O plano é ativado somente após a confirmação pelo servidor.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
