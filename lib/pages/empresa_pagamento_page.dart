import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/pagamento_assinatura_service.dart';
import '../services/empresa_service.dart';

class EmpresaPagamentoPage extends StatefulWidget {
  final String plano;
  final String precoMensal;

  const EmpresaPagamentoPage({
    super.key,
    this.plano = 'Essencial',
    this.precoMensal = 'R\$ 39,90',
  });

  @override
  State<EmpresaPagamentoPage> createState() => _EmpresaPagamentoPageState();
}

enum _FormaPagamento { pix, cartao }

class _EmpresaPagamentoPageState extends State<EmpresaPagamentoPage> {
  _FormaPagamento _forma = _FormaPagamento.pix;
  final TextEditingController _emailPagadorController = TextEditingController();

  bool _carregando = false;
  bool _consultando = false;

  String? _chaveIdempotencia;
  String? _codigoPix;
  String? _status;
  String? _mensagemErro;

  int? _pagamentoId;
  bool _planoAtivado = false;
  int? _assinaturaId;
  String? _statusAssinatura;
  String? _urlAutorizacao;
  String? _chaveRecorrente;
  bool _consultandoAssinatura = false;
  bool _recuperandoAssinatura = false;
  bool _inicializandoTentativa = true;
  bool _tentativaIncerta = false;
  String? _chaveArmazenamento;
  String? _emailTentativa;
  String? _planoTentativa;

  @override
  void initState() {
    super.initState();
    _inicializarTentativa();
  }

  @override
  void dispose() {
    _emailPagadorController.dispose();
    super.dispose();
  }

  Future<void> _inicializarTentativa() async {
    try {
      final token = await EmpresaService.obterTokenEmpresa();
      if (token == null) throw StateError('Sessão empresarial não encontrada.');
      final partes = token.split('.');
      if (partes.length != 3) throw StateError('Sessão empresarial inválida.');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
      );
      if (payload is! Map<String, dynamic> || payload['tipo'] != 'EMPRESA') {
        throw StateError('Acesso exclusivo para empresas.');
      }
      final empresaId = int.tryParse(payload['sub']?.toString() ?? '');
      final exp = payload['exp'];
      final agora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (empresaId == null || empresaId <= 0 || exp is! num || exp <= agora) {
        throw StateError('Sessão empresarial expirada ou inválida.');
      }
      final chave = 'entregueja_assinatura_tentativa_empresa_$empresaId';
      final prefs = await SharedPreferences.getInstance();
      final registro = prefs.getString(chave);
      if (!mounted) return;
      _chaveArmazenamento = chave;
      if (registro != null) {
        final dados = jsonDecode(registro);
        if (dados is! Map<String, dynamic> ||
            dados['chave'] is! String ||
            dados['email'] is! String ||
            dados['plano'] is! String) {
          throw StateError(
            'Tentativa anterior inválida. Verifique a assinatura antes de prosseguir.',
          );
        }
        _chaveRecorrente = dados['chave'] as String;
        _emailTentativa = dados['email'] as String;
        _planoTentativa = dados['plano'] as String;
        _emailPagadorController.text = _emailTentativa!;
        _tentativaIncerta = true;
        _forma = _FormaPagamento.cartao;
      }
      await _recuperarAssinaturaExistente();
    } catch (erro) {
      if (mounted) {
        setState(() {
          _tentativaIncerta = true;
          _mensagemErro =
              'Não foi possível verificar a tentativa anterior: $erro';
        });
      }
    } finally {
      if (mounted) setState(() => _inicializandoTentativa = false);
    }
  }

  Future<void> _salvarTentativa(String email) async {
    final chave = _chaveArmazenamento;
    if (chave == null)
      throw StateError('Não foi possível identificar a empresa.');
    final prefs = await SharedPreferences.getInstance();
    final idempotencia = _chaveRecorrente ??= _gerarUuid();
    await prefs.setString(
      chave,
      jsonEncode({'chave': idempotencia, 'email': email, 'plano': _planoApi}),
    );
    _emailTentativa = email;
    _planoTentativa = _planoApi;
    _tentativaIncerta = true;
  }

  Future<void> _limparTentativa() async {
    final chave = _chaveArmazenamento;
    if (chave != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(chave);
    }
    _chaveRecorrente = null;
    _emailTentativa = null;
    _planoTentativa = null;
    _tentativaIncerta = false;
  }

  Future<void> _recuperarAssinaturaExistente() async {
    if (_recuperandoAssinatura || _carregando) return;
    setState(() {
      _recuperandoAssinatura = true;
      _mensagemErro = null;
    });
    try {
      final assinaturas =
          await PagamentoAssinaturaService.listarAssinaturasRecorrentes();
      if (!mounted) return;
      final ativas = assinaturas.where((assinatura) {
        final status = assinatura['status']?.toString().toUpperCase();
        return status == 'PENDENTE' ||
            status == 'AUTORIZADA' ||
            status == 'PAUSADA';
      }).toList();
      if (ativas.isNotEmpty) {
        ativas.sort((a, b) {
          final aId = int.tryParse(a['assinaturaId'].toString()) ?? 0;
          final bId = int.tryParse(b['assinaturaId'].toString()) ?? 0;
          return bId.compareTo(aId);
        });
        final assinatura = ativas.first;
        setState(() {
          _forma = _FormaPagamento.cartao;
        });
        _atualizarAssinatura(assinatura);
        await _limparTentativa();
      }
    } catch (erro) {
      if (mounted) {
        setState(
          () => _mensagemErro =
              'Não foi possível verificar suas assinaturas: $erro',
        );
      }
    } finally {
      if (mounted) setState(() => _recuperandoAssinatura = false);
    }
  }

  String _gerarUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hexadecimal = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hexadecimal.substring(0, 8)}-'
        '${hexadecimal.substring(8, 12)}-'
        '${hexadecimal.substring(12, 16)}-'
        '${hexadecimal.substring(16, 20)}-'
        '${hexadecimal.substring(20)}';
  }

  String get _planoApi {
    return widget.plano.trim().toUpperCase();
  }

  bool get _pagamentoFinalizado {
    return _status == 'APROVADO' ||
        _status == 'RECUSADO' ||
        _status == 'CANCELADO' ||
        _status == 'REEMBOLSADO';
  }

  void _atualizarPagamento(Map<String, dynamic> dados) {
    final id = dados['pagamentoId'];

    if (id is! int || id <= 0) {
      throw const PagamentoAssinaturaException(
        'O servidor não retornou um identificador válido para o pagamento.',
      );
    }

    final status = dados['status'];
    final codigo = dados['pixCopiaECola'];

    setState(() {
      _pagamentoId = id;
      _status = status is String ? status.toUpperCase() : 'PENDENTE';
      _codigoPix = codigo is String && codigo.isNotEmpty ? codigo : null;
      _planoAtivado = dados['planoAtivado'] == true;
      _mensagemErro = null;
    });
  }

  Future<void> _criarPix() async {
    if (_carregando || _consultando || _pagamentoId != null) {
      return;
    }

    if (_planoApi != 'ESSENCIAL' && _planoApi != 'PROFISSIONAL') {
      setState(() {
        _mensagemErro = 'Selecione um plano pago válido.';
      });
      return;
    }

    _chaveIdempotencia ??= _gerarUuid();

    setState(() {
      _carregando = true;
      _mensagemErro = null;
    });

    try {
      final dados = await PagamentoAssinaturaService.criarPix(
        plano: _planoApi,
        chaveIdempotencia: _chaveIdempotencia!,
      );

      if (!mounted) return;

      _atualizarPagamento(dados);
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _mensagemErro = erro.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    }
  }

  Future<void> _consultarPagamento() async {
    final id = _pagamentoId;

    if (id == null || _consultando || _carregando) {
      return;
    }

    setState(() {
      _consultando = true;
      _mensagemErro = null;
    });

    try {
      final dados = await PagamentoAssinaturaService.consultarPix(
        pagamentoId: id,
      );

      if (!mounted) return;

      _atualizarPagamento(dados);
    } catch (erro) {
      if (!mounted) return;

      setState(() {
        _mensagemErro = erro.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _consultando = false;
        });
      }
    }
  }

  Future<void> _copiarCodigo() async {
    final codigo = _codigoPix;

    if (codigo == null || codigo.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: codigo));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código Pix copiado com sucesso.')),
    );
  }

  void _atualizarAssinatura(Map<String, dynamic> dados) {
    final id = dados['assinaturaId'];
    if (id is! int || id <= 0) {
      throw const PagamentoAssinaturaException(
        'O servidor não retornou um identificador válido para a assinatura.',
      );
    }
    final url = dados['urlAutorizacao']?.toString();
    setState(() {
      _assinaturaId = id;
      _statusAssinatura =
          dados['status']?.toString().toUpperCase() ?? 'PENDENTE';
      _urlAutorizacao = url != null && url.isNotEmpty ? url : null;
      _mensagemErro = null;
    });
  }

  Future<void> _abrirAutorizacao() async {
    final url = _urlAutorizacao;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !(uri.host == 'mercadopago.com.br' ||
            uri.host.endsWith('.mercadopago.com.br') ||
            uri.host == 'mercadopago.com' ||
            uri.host.endsWith('.mercadopago.com'))) {
      setState(
        () =>
            _mensagemErro = 'A URL de autorização do Mercado Pago é inválida.',
      );
      return;
    }
    try {
      final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abriu && mounted) {
        setState(
          () => _mensagemErro = 'Não foi possível abrir o Mercado Pago.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _mensagemErro = 'Não foi possível abrir o Mercado Pago.',
        );
      }
    }
  }

  Future<void> _criarAssinaturaCartao() async {
    if (_carregando ||
        _consultandoAssinatura ||
        _recuperandoAssinatura ||
        _inicializandoTentativa ||
        _tentativaIncerta ||
        _assinaturaId != null) {
      return;
    }
    if (_planoApi != 'ESSENCIAL' && _planoApi != 'PROFISSIONAL') {
      setState(() => _mensagemErro = 'Selecione um plano pago válido.');
      return;
    }
    final emailPagador = _emailPagadorController.text.trim();
    if (emailPagador.isEmpty ||
        emailPagador.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(emailPagador)) {
      setState(
        () => _mensagemErro =
            'Informe um e-mail válido do responsável pelo pagamento.',
      );
      return;
    }
    if (_emailTentativa != null &&
        (_emailTentativa != emailPagador || _planoTentativa != _planoApi)) {
      setState(
        () => _mensagemErro =
            'Existe uma tentativa anterior com outros dados. Consulte a assinatura antes de continuar.',
      );
      return;
    }
    setState(() {
      _carregando = true;
      _mensagemErro = null;
    });
    try {
      await _salvarTentativa(emailPagador);
      final dados = await PagamentoAssinaturaService.criarAssinaturaRecorrente(
        plano: _planoApi,
        chaveIdempotencia: _chaveRecorrente!,
        emailPagador: emailPagador,
      );
      if (!mounted) return;
      _atualizarAssinatura(dados);
      await _limparTentativa();
      if (_urlAutorizacao != null && _statusAssinatura == 'PENDENTE') {
        await _abrirAutorizacao();
      }
    } on PagamentoAssinaturaException catch (erro) {
      if (!mounted) return;
      if (erro.statusCode == 409) {
        setState(() => _carregando = false);
        await _recuperarAssinaturaExistente();
        if (mounted && _assinaturaId == null && _mensagemErro == null) {
          setState(() => _mensagemErro = erro.toString());
        }
      } else {
        setState(() => _mensagemErro = erro.toString());
      }
    } catch (erro) {
      if (mounted) setState(() => _mensagemErro = erro.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _consultarAssinaturaCartao() async {
    final id = _assinaturaId;
    if (id == null || _consultandoAssinatura || _carregando) return;
    setState(() {
      _consultandoAssinatura = true;
      _mensagemErro = null;
    });
    try {
      final dados =
          await PagamentoAssinaturaService.consultarAssinaturaRecorrente(
            assinaturaId: id,
          );
      if (mounted) _atualizarAssinatura(dados);
    } catch (erro) {
      if (mounted) setState(() => _mensagemErro = erro.toString());
    } finally {
      if (mounted) setState(() => _consultandoAssinatura = false);
    }
  }

  Widget _construirCartao(ThemeData theme) {
    final status = _statusAssinatura ?? 'PENDENTE';
    final autorizada = status == 'AUTORIZADA';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assinatura nº $_assinaturaId',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Status: $status'),
                const SizedBox(height: 8),
                Text(
                  autorizada
                      ? 'Cartão autorizado. A ativação do plano depende da confirmação da cobrança pelo servidor.'
                      : status == 'PENDENTE'
                      ? 'Autorize a assinatura no Mercado Pago. Depois, volte e consulte o status.'
                      : 'Consulte o gerenciamento de assinaturas para verificar os próximos passos.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_urlAutorizacao != null && status == 'PENDENTE') ...[
          FilledButton.icon(
            onPressed: _carregando ? null : _abrirAutorizacao,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir autorização no Mercado Pago'),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _consultandoAssinatura ? null : _consultarAssinaturaCartao,
          icon: _consultandoAssinatura
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(
            _consultandoAssinatura
                ? 'Consultando...'
                : 'Consultar status da assinatura',
          ),
        ),
      ],
    );
  }

  Widget _construirStatus(ThemeData theme) {
    final status = _status;

    if (status == null) {
      return const SizedBox.shrink();
    }

    String mensagem;
    IconData icone;
    Color cor;

    switch (status) {
      case 'APROVADO':
        mensagem = _planoAtivado
            ? 'Pagamento aprovado! Seu plano foi ativado.'
            : 'Pagamento aprovado. A ativação do plano ainda não foi confirmada.';
        icone = Icons.check_circle_outline;
        cor = Colors.green;
        break;
      case 'RECUSADO':
        mensagem = 'O pagamento foi recusado.';
        icone = Icons.cancel_outlined;
        cor = theme.colorScheme.error;
        break;
      case 'CANCELADO':
        mensagem = 'O pagamento foi cancelado.';
        icone = Icons.cancel_outlined;
        cor = theme.colorScheme.error;
        break;
      case 'REEMBOLSADO':
        mensagem = 'O pagamento foi reembolsado.';
        icone = Icons.info_outline;
        cor = theme.colorScheme.error;
        break;
      default:
        mensagem = 'Aguardando confirmação do pagamento.';
        icone = Icons.schedule;
        cor = theme.colorScheme.primary;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: cor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mensagem,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_pagamentoId != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Pagamento nº $_pagamentoId',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirPix(ThemeData theme) {
    final codigo = _codigoPix;

    if (_pagamentoId == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _construirStatus(theme),
        const SizedBox(height: 16),
        if (codigo != null && !_pagamentoFinalizado) ...[
          Text('QR Code Pix', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: codigo,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Pix copia e cola', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: codigo),
            readOnly: true,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _copiarCodigo,
            icon: const Icon(Icons.copy),
            label: const Text('Copiar código Pix'),
          ),
          const SizedBox(height: 16),
        ],
        if (!_pagamentoFinalizado || !_planoAtivado)
          FilledButton.icon(
            onPressed: _consultando ? null : _consultarPagamento,
            icon: _consultando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(
              _consultando
                  ? 'Consultando pagamento...'
                  : 'Consultar status do pagamento',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isPix = _forma == _FormaPagamento.pix;
    final temPagamento = _pagamentoId != null || _assinaturaId != null;
    final bloqueado =
        _carregando || _recuperandoAssinatura || _inicializandoTentativa;

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
                          'Plano ${widget.plano}',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.precoMensal,
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
                        Text(
                          'Pagamento da mensalidade selecionada.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Forma de pagamento', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: RadioGroup<_FormaPagamento>(
                    groupValue: _forma,
                    onChanged: (value) {
                      if (temPagamento ||
                          bloqueado ||
                          _tentativaIncerta ||
                          value == null)
                        return;

                      setState(() {
                        _forma = value;
                        _mensagemErro = null;
                      });
                    },
                    child: Column(
                      children: [
                        const RadioListTile<_FormaPagamento>(
                          value: _FormaPagamento.pix,
                          title: Text('Pix'),
                          subtitle: Text(
                            'Pagamento por QR Code ou código copia e cola',
                          ),
                          secondary: Icon(Icons.qr_code_2),
                        ),
                        const Divider(height: 1),
                        const RadioListTile<_FormaPagamento>(
                          value: _FormaPagamento.cartao,
                          title: Text('Cartão de crédito'),
                          subtitle: Text(
                            'Pagamento com cartão via provedor seguro',
                          ),
                          secondary: Icon(Icons.credit_card),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isPix && _assinaturaId == null) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailPagadorController,
                    enabled: !bloqueado && !_tentativaIncerta,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-mail do responsável pelo pagamento',
                      hintText: 'pagador@exemplo.com',
                      border: OutlineInputBorder(),
                      helperText: 'Pode ser diferente do e-mail da empresa.',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isPix
                              ? 'O pagamento Pix será gerado pelo Mercado Pago. '
                                    'A confirmação será consultada diretamente no servidor.'
                              : 'A autorização do cartão será feita no Mercado Pago. A cobrança recorrente e a ativação do plano dependem da confirmação do servidor.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_mensagemErro != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: colors.error),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_mensagemErro!)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_tentativaIncerta && _assinaturaId == null && !isPix) ...[
                  const Text(
                    'Existe uma tentativa de assinatura cujo resultado ainda não foi confirmado. '
                    'Para evitar cobranças duplicadas, não será criada outra assinatura.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: bloqueado ? null : _recuperarAssinaturaExistente,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Consultar assinatura existente'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_recuperandoAssinatura || _inicializandoTentativa) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text('Verificando assinaturas existentes...'),
                  ),
                ] else if (isPix && _pagamentoId != null)
                  _construirPix(theme)
                else if (!isPix && _assinaturaId != null)
                  _construirCartao(theme)
                else
                  FilledButton.icon(
                    onPressed: bloqueado || (!isPix && _tentativaIncerta)
                        ? null
                        : isPix
                        ? _criarPix
                        : _criarAssinaturaCartao,
                    icon: _carregando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(isPix ? Icons.qr_code : Icons.lock_outline),
                    label: Text(
                      _carregando
                          ? (isPix ? 'Gerando Pix...' : 'Criando assinatura...')
                          : isPix
                          ? 'Continuar com Pix'
                          : 'Continuar com cartão',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Confira os dados antes de continuar. A assinatura no cartão pode gerar cobranças mensais reais.',
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
