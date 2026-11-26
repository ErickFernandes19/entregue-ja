import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/assinatura_service.dart';
import '../services/empresa_service.dart';

class EmpresaPlanosPage extends StatefulWidget {
  const EmpresaPlanosPage({super.key});

  @override
  State<EmpresaPlanosPage> createState() => _EmpresaPlanosPageState();
}

class _EmpresaPlanosPageState extends State<EmpresaPlanosPage> {
  bool _carregando = true;
  String? _erro;
  String? _planoAtual;
  bool _testeAtivo = false;
  bool _testeUtilizado = false;
  bool _ativandoTeste = false;
  bool _consultando = false;
  bool _navegando = false;
  bool _confirmandoTeste = false;
  String? _tokenConsulta;
  DateTime? _fimTeste;

  @override
  void initState() {
    super.initState();
    _carregarAssinatura();
  }

  bool get _ocupado =>
      _carregando || _navegando || _confirmandoTeste || _ativandoTeste;

  Future<String> _obterSessao() async {
    final email = await EmpresaService.empresaLogada();
    final token = await EmpresaService.obterTokenEmpresa();
    if (email == null || token == null || token.trim().isEmpty) {
      throw const ApiException(
        'Sua sessão expirou. Entre novamente na sua conta.',
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

  String _mensagemErro(Object erro, String mensagemPadrao) {
    if (erro is AssinaturaException) {
      return erro.mensagem;
    }
    return ApiService.mensagemErro(erro, mensagemPadrao: mensagemPadrao);
  }

  void _mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  void _limparAssinatura() {
    _tokenConsulta = null;
    _planoAtual = null;
    _testeAtivo = false;
    _testeUtilizado = false;
    _fimTeste = null;
  }

  Future<void> _carregarAssinatura({bool duranteOperacao = false}) async {
    if (!mounted ||
        _consultando ||
        (!duranteOperacao &&
            (_navegando || _confirmandoTeste || _ativandoTeste))) {
      return;
    }
    setState(() {
      _consultando = true;
      _carregando = true;
      _erro = null;
    });

    try {
      final token = await _obterSessao();
      if (!mounted) return;
      if (_tokenConsulta != null && _tokenConsulta != token) {
        setState(_limparAssinatura);
      }
      final assinatura = await AssinaturaService.buscarAtual();
      await _conferirSessao(token);
      if (!mounted) return;
      final historico = await AssinaturaService.buscarHistorico();
      await _conferirSessao(token);
      if (!mounted) return;

      final status = assinatura?['status']?.toString().toUpperCase();
      final plano = assinatura?['plano']?.toString().toUpperCase();
      final ativa = status == 'ATIVA';
      if (assinatura != null && (status == null || status.trim().isEmpty)) {
        throw const FormatException('Status da assinatura inválido');
      }
      if (ativa &&
          !const {'GRATUITO', 'ESSENCIAL', 'PROFISSIONAL'}.contains(plano)) {
        throw const FormatException('Plano ativo inválido');
      }
      final testeAtivo = ativa && assinatura?['testeGratuito'] == true;
      final fimTeste = DateTime.tryParse(
        assinatura?['dataVencimento']?.toString() ?? '',
      );
      final testeUtilizado =
          testeAtivo || historico.any((item) => item['testeGratuito'] == true);

      setState(() {
        _tokenConsulta = token;
        _planoAtual = ativa ? plano : null;
        _testeAtivo = testeAtivo;
        _testeUtilizado = testeUtilizado;
        _fimTeste = testeAtivo ? fimTeste : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiException && e.statusCode == 401) {
          _limparAssinatura();
        }
        _erro = _mensagemErro(e, 'Não foi possível consultar sua assinatura.');
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

  Future<void> _abrirGerenciamento() async {
    if (_ocupado || !mounted) return;
    setState(() => _navegando = true);
    try {
      await _obterSessao();
      if (!mounted) return;
      await context.push('/empresa/assinatura/gerenciamento');
      if (mounted) {
        await _carregarAssinatura(duranteOperacao: true);
      }
    } catch (e) {
      _mostrarMensagem(
        _mensagemErro(
          e,
          'Não foi possível abrir o gerenciamento da assinatura.',
        ),
      );
      if (mounted && e is ApiException && e.statusCode == 401) {
        await _carregarAssinatura(duranteOperacao: true);
      }
    } finally {
      if (mounted) setState(() => _navegando = false);
    }
  }

  Future<void> _abrirPagamento(String nome, String preco) async {
    if (!mounted || _ocupado || _erro != null || _tokenConsulta == null) {
      return;
    }
    final plano = nome.toUpperCase();
    if (!const {'ESSENCIAL', 'PROFISSIONAL'}.contains(plano) ||
        plano == _planoAtual) {
      return;
    }
    final token = _tokenConsulta!;
    setState(() => _navegando = true);
    try {
      await _conferirSessao(token);
      if (!mounted) return;
      await context.push(
        '/empresa/pagamento',
        extra: <String, dynamic>{'plano': nome, 'precoMensal': preco},
      );
      if (mounted) {
        await _carregarAssinatura(duranteOperacao: true);
      }
    } catch (e) {
      _mostrarMensagem(
        _mensagemErro(e, 'Não foi possível abrir a tela de pagamento.'),
      );
      if (mounted && e is ApiException && e.statusCode == 401) {
        await _carregarAssinatura(duranteOperacao: true);
      }
    } finally {
      if (mounted) setState(() => _navegando = false);
    }
  }

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  Future<void> _iniciarTeste() async {
    if (!mounted ||
        _ocupado ||
        _erro != null ||
        _tokenConsulta == null ||
        _testeUtilizado ||
        _planoAtual != 'GRATUITO') {
      return;
    }

    final token = _tokenConsulta!;
    setState(() => _confirmandoTeste = true);
    try {
      await _conferirSessao(token);
      if (!mounted) return;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ativar teste gratuito?'),
          content: const Text(
            'Você terá acesso ao Essencial por 14 dias, sem cobrança. '
            'O teste pode ser utilizado apenas uma vez por empresa. '
            'Ao terminar, sua empresa retornará ao plano Gratuito '
            'se não houver contratação de um plano pago.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Ativar 14 dias'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;
      await _conferirSessao(token);
      if (!mounted) return;
      setState(() => _ativandoTeste = true);
      await AssinaturaService.iniciarTesteEssencial();
      if (!mounted) return;
      await _conferirSessao(token);
      if (!mounted) return;
      await _carregarAssinatura(duranteOperacao: true);
      if (!mounted) return;
      if (_erro == null &&
          _tokenConsulta == token &&
          _planoAtual == 'ESSENCIAL' &&
          _testeAtivo) {
        _mostrarMensagem('Teste Essencial ativado com sucesso!');
      } else {
        _mostrarMensagem(
          'Não foi possível confirmar a ativação. Consulte sua assinatura antes de tentar novamente.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarMensagem(
        _mensagemErro(
          e,
          'Não foi possível confirmar a ativação. Consulte sua assinatura antes de tentar novamente.',
        ),
      );
      await _carregarAssinatura(duranteOperacao: true);
    } finally {
      if (mounted) {
        setState(() {
          _ativandoTeste = false;
          _confirmandoTeste = false;
        });
      }
    }
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
              'Um plano para cada etapa da sua empresa',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Escolha a capacidade mensal ideal para sua operação. Os entregadores vinculados utilizam os recursos incluídos no plano da empresa.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _ocupado ? null : _abrirGerenciamento,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Gerenciar assinatura'),
              ),
            ),
            const SizedBox(height: 18),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
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
              )
            else if (_planoAtual == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nenhum plano ativo foi identificado para esta empresa.',
                  ),
                ),
              ),
            const SizedBox(height: 18),
            _CartaoPlano(
              nome: 'Gratuito',
              preco: 'R\$ 0,00',
              entregadores: 1,
              entregasPorMes: 100,
              gratuito: true,
              planoAtual: _planoAtual == 'GRATUITO',
              verificando: _ocupado || _erro != null,
            ),
            const SizedBox(height: 14),
            _CartaoPlano(
              nome: 'Essencial',
              preco: 'R\$ 39,90',
              entregadores: 3,
              entregasPorMes: 1000,
              destaque: true,
              planoAtual: _planoAtual == 'ESSENCIAL',
              emTeste: _testeAtivo,
              verificando: _ocupado || _erro != null,
              onEscolher: () => _abrirPagamento('Essencial', 'R\$ 39,90'),
            ),
            const SizedBox(height: 14),
            _CartaoPlano(
              nome: 'Profissional',
              preco: 'R\$ 79,90',
              entregadores: 10,
              entregasPorMes: 5000,
              planoAtual: _planoAtual == 'PROFISSIONAL',
              verificando: _ocupado || _erro != null,
              onEscolher: () => _abrirPagamento('Profissional', 'R\$ 79,90'),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.workspace_premium_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Experimente o Essencial por 14 dias',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Teste gratuito e opcional, disponível uma única vez por empresa.',
                    ),
                    const SizedBox(height: 14),
                    const _Beneficio(texto: 'Até 3 entregadores vinculados'),
                    const SizedBox(height: 10),
                    const _Beneficio(texto: 'Até 500 entregas durante o teste'),
                    const SizedBox(height: 10),
                    const _Beneficio(texto: 'Acesso aos recursos do Essencial'),
                    const SizedBox(height: 10),
                    const _Beneficio(texto: 'Sem cobrança durante os 14 dias'),
                    const SizedBox(height: 14),
                    Text(
                      'Ao final do teste, caso não contrate um plano, a empresa retorna ao Gratuito.',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (_testeAtivo && _fimTeste != null) ...[
                      const SizedBox(height: 12),
                      Text('Término previsto: ${_formatarData(_fimTeste!)}'),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            _ocupado ||
                                _erro != null ||
                                _testeUtilizado ||
                                _planoAtual != 'GRATUITO'
                            ? null
                            : _iniciarTeste,
                        icon: _ativandoTeste
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _testeAtivo
                                    ? Icons.check_circle_outline
                                    : Icons.workspace_premium_outlined,
                              ),
                        label: Text(
                          _ativandoTeste
                              ? 'Ativando teste...'
                              : _testeAtivo
                              ? 'Teste em andamento'
                              : _testeUtilizado
                              ? 'Teste já utilizado'
                              : _planoAtual != 'GRATUITO'
                              ? 'Disponível no plano Gratuito'
                              : 'Experimentar 14 dias grátis',
                        ),
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

class _CartaoPlano extends StatelessWidget {
  final String nome;
  final String preco;
  final int entregadores;
  final int entregasPorMes;
  final bool gratuito;
  final bool destaque;
  final bool planoAtual;
  final bool emTeste;
  final bool verificando;
  final VoidCallback? onEscolher;

  const _CartaoPlano({
    required this.nome,
    required this.preco,
    required this.entregadores,
    required this.entregasPorMes,
    this.gratuito = false,
    this.destaque = false,
    this.planoAtual = false,
    this.emTeste = false,
    this.verificando = false,
    this.onEscolher,
  });

  String get _entregasFormatadas {
    return entregasPorMes.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
  }

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
                    label: Text(emTeste ? 'Em teste' : 'Atual'),
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
            _Beneficio(
              texto: entregadores == 1
                  ? '1 entregador vinculado'
                  : '$entregadores entregadores vinculados',
            ),
            const SizedBox(height: 12),
            _Beneficio(texto: '$_entregasFormatadas entregas por mês'),
            const SizedBox(height: 12),
            const _Beneficio(texto: 'Gestão e acompanhamento de entregas'),
            const SizedBox(height: 12),
            const _Beneficio(texto: 'Mapas e navegação'),
            const SizedBox(height: 12),
            const _Beneficio(texto: 'Histórico de entregas'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: verificando || planoAtual || gratuito
                    ? null
                    : onEscolher,
                icon: Icon(
                  planoAtual || gratuito
                      ? Icons.check_circle_outline
                      : Icons.credit_card,
                ),
                label: Text(
                  planoAtual
                      ? (emTeste ? 'Teste ativo' : 'Seu plano atual')
                      : gratuito
                      ? 'Plano gratuito'
                      : 'Escolher plano',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Beneficio extends StatelessWidget {
  final String texto;

  const _Beneficio({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(texto)),
      ],
    );
  }
}
