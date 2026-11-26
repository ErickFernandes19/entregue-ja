import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/assinatura_service.dart';
import '../services/auth_service.dart';
import 'entregador_pagamento_page.dart';

class EntregadorPlanosPage extends StatefulWidget {
  const EntregadorPlanosPage({super.key});

  @override
  State<EntregadorPlanosPage> createState() => _EntregadorPlanosPageState();
}

class _EntregadorPlanosPageState extends State<EntregadorPlanosPage> {
  bool _carregando = true;
  bool _consultando = false;
  bool _navegando = false;
  String? _erro;
  String? _planoAtual;
  String? _tokenConsulta;

  bool get _ocupado => _carregando || _navegando;

  bool get _podeSelecionar =>
      !_ocupado && _erro == null && _tokenConsulta != null;

  @override
  void initState() {
    super.initState();
    _carregarAssinatura();
  }

  Future<String> _obterSessao() async {
    final token = await AuthService.obterToken();
    final email = await AuthService.usuarioLogado();
    if (token == null ||
        token.trim().isEmpty ||
        email == null ||
        email.trim().isEmpty ||
        await AuthService.obterToken() != token) {
      throw const ApiException(
        'Sua sessão expirou ou foi alterada. Entre novamente como entregador.',
        statusCode: 401,
      );
    }
    return token;
  }

  Future<void> _conferirSessao(String token) async {
    if (await _obterSessao() != token) {
      throw const ApiException(
        'Sua sessão foi alterada. Atualize os dados da assinatura.',
        statusCode: 401,
      );
    }
  }

  void _limparAssinatura() {
    _planoAtual = null;
    _tokenConsulta = null;
  }

  Future<void> _carregarAssinatura({bool duranteNavegacao = false}) async {
    if (!mounted || _consultando || (_navegando && !duranteNavegacao)) {
      return;
    }

    setState(() {
      _consultando = true;
      _carregando = true;
      _erro = null;
    });

    String? token;
    try {
      token = await _obterSessao();
      if (!mounted) return;
      if (_tokenConsulta != null && _tokenConsulta != token) {
        setState(_limparAssinatura);
      }

      final assinatura = await AssinaturaService.buscarAtual(
        tipoConta: TipoContaAssinatura.entregador,
      );
      await _conferirSessao(token);
      if (!mounted) return;

      final plano = assinatura?['plano']?.toString().trim().toUpperCase();
      final status = assinatura?['status']?.toString().trim().toUpperCase();
      if (assinatura != null &&
          (!const {'GRATUITO', 'ESSENCIAL', 'PROFISSIONAL'}.contains(plano) ||
              !const {
                'ATIVA',
                'PENDENTE',
                'CANCELADA',
                'EXPIRADA',
              }.contains(status))) {
        throw const ApiException(
          'O servidor retornou dados inválidos da assinatura. Atualize e tente novamente.',
        );
      }

      setState(() {
        _planoAtual = status == 'ATIVA' ? plano : null;
        _tokenConsulta = token;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (token == null || (e is ApiException && e.statusCode == 401)) {
          _limparAssinatura();
        }
        _erro = ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível consultar sua assinatura.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _consultando = false;
          _carregando = false;
        });
      }
    }
  }

  Future<void> _navegar(
    Future<void> Function() abrir, {
    required bool pagamento,
  }) async {
    if (!mounted || _ocupado || (pagamento && !_podeSelecionar)) {
      return;
    }

    setState(() => _navegando = true);
    try {
      final token = await _obterSessao();
      if (!mounted) return;
      if (pagamento && token != _tokenConsulta) {
        throw const ApiException(
          'Sua sessão foi alterada. Atualize os dados da assinatura.',
          statusCode: 401,
        );
      }
      await abrir();
      if (mounted) {
        await _carregarAssinatura(duranteNavegacao: true);
      }
    } catch (e) {
      if (!mounted) return;
      final mensagem = ApiService.mensagemErro(
        e,
        mensagemPadrao: pagamento
            ? 'Não foi possível abrir a tela de pagamento.'
            : 'Não foi possível abrir o gerenciamento da assinatura.',
      );
      if (e is ApiException && e.statusCode == 401) {
        setState(() {
          _limparAssinatura();
          _erro = mensagem;
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensagem)));
    } finally {
      if (mounted) setState(() => _navegando = false);
    }
  }

  Future<void> _abrirPagamento(String plano, String preco) {
    return _navegar(() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              EntregadorPagamentoPage(plano: plano, precoMensal: preco),
        ),
      );
    }, pagamento: true);
  }

  Future<void> _abrirGerenciamento() {
    return _navegar(() async {
      await context.push('/entregador/assinatura/gerenciamento');
    }, pagamento: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planos e Assinaturas'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _ocupado ? null : _carregarAssinatura,
            tooltip: 'Atualizar assinatura',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarAssinatura,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Um plano para cada etapa das suas entregas',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Compare os planos para trabalhar com entregas independentes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _ocupado ? null : _abrirGerenciamento,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Gerenciar assinatura'),
              ),
            ),
            if (_carregando) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ] else if (_erro != null) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_erro!),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _ocupado ? null : _carregarAssinatura,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _CartaoPlanoEntregador(
              nome: 'Gratuito',
              preco: 'R\$ 0,00',
              beneficios: const [
                'Até 20 entregas por dia',
                'Cadastro manual e leitura de QR Code',
                'Mapa e navegação',
              ],
              gratuito: true,
              planoAtual:
                  !_carregando && _erro == null && _planoAtual == 'GRATUITO',
            ),
            const SizedBox(height: 14),
            _CartaoPlanoEntregador(
              nome: 'Essencial',
              preco: 'R\$ 9,90',
              beneficios: const [
                'Até 50 entregas por dia',
                'Cadastro manual e leitura de QR Code',
                'Mapa e navegação',
                'Histórico de entregas',
                'Relatórios de desempenho',
              ],
              planoAtual:
                  !_carregando && _erro == null && _planoAtual == 'ESSENCIAL',
              onSelecionar: _podeSelecionar
                  ? () => _abrirPagamento('Essencial', 'R\$ 9,90')
                  : null,
            ),
            const SizedBox(height: 14),
            _CartaoPlanoEntregador(
              nome: 'Profissional',
              preco: 'R\$ 19,90',
              beneficios: const [
                'Entregas ilimitadas',
                'Cadastro manual e leitura de QR Code',
                'Mapa e navegação',
                'Histórico completo',
                'Relatórios avançados',
              ],
              destaque: true,
              planoAtual:
                  !_carregando &&
                  _erro == null &&
                  _planoAtual == 'PROFISSIONAL',
              onSelecionar: _podeSelecionar
                  ? () => _abrirPagamento('Profissional', 'R\$ 19,90')
                  : null,
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Entregas atribuídas por empresas vinculadas não exigem assinatura pessoal. A contratação dos planos pagos depende da habilitação do pagamento para entregadores.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoPlanoEntregador extends StatelessWidget {
  final String nome;
  final String preco;
  final List<String> beneficios;
  final bool gratuito;
  final bool destaque;
  final bool planoAtual;
  final VoidCallback? onSelecionar;

  const _CartaoPlanoEntregador({
    required this.nome,
    required this.preco,
    required this.beneficios,
    this.gratuito = false,
    this.destaque = false,
    this.planoAtual = false,
    this.onSelecionar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: planoAtual || destaque
              ? colors.primary
              : colors.outlineVariant,
          width: planoAtual || destaque ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    nome,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (planoAtual)
                  Chip(
                    avatar: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Atual'),
                    backgroundColor: colors.primaryContainer,
                  )
                else if (destaque)
                  Chip(
                    label: const Text('Popular'),
                    backgroundColor: colors.primaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  preco,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
                if (!gratuito)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 5),
                    child: Text('/mês', style: theme.textTheme.bodyMedium),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            ...beneficios.map(
              (beneficio) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(beneficio)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: planoAtual || gratuito ? null : onSelecionar,
                icon: Icon(
                  planoAtual
                      ? Icons.check_circle_outline
                      : gratuito
                      ? Icons.check_circle_outline
                      : Icons.arrow_forward_outlined,
                ),
                label: Text(
                  planoAtual
                      ? 'Seu plano atual'
                      : gratuito
                      ? 'Plano gratuito'
                      : 'Selecionar plano',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
