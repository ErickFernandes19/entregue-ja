import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/pagamento_assinatura_service.dart';

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

  bool _carregando = false;
  bool _consultando = false;

  String? _chaveIdempotencia;
  String? _codigoPix;
  String? _status;
  String? _mensagemErro;

  int? _pagamentoId;
  bool _planoAtivado = false;

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

  void _mostrarCartaoIndisponivel() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cartão de crédito'),
        content: const Text(
          'A contratação por cartão ainda não está disponível nesta tela. '
          'Nenhuma cobrança será realizada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
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
    final temPagamento = _pagamentoId != null;

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
                    onChanged: temPagamento
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _forma = value);
                            }
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
                              : 'O pagamento por cartão ainda não está disponível nesta tela.',
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
                if (isPix && temPagamento)
                  _construirPix(theme)
                else
                  FilledButton.icon(
                    onPressed: _carregando
                        ? null
                        : isPix
                        ? _criarPix
                        : _mostrarCartaoIndisponivel,
                    icon: _carregando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(isPix ? Icons.qr_code : Icons.lock_outline),
                    label: Text(
                      _carregando
                          ? 'Gerando Pix...'
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
                  'Ambiente de testes. Não realize pagamentos reais durante a validação.',
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
