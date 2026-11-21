import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assinatura_service.dart';

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
  DateTime? _fimTeste;
  Map<String, dynamic>? _consumo;

  @override
  void initState() {
    super.initState();
    _carregarAssinatura();
  }

  Future<void> _carregarAssinatura() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final assinatura = await AssinaturaService.buscarAtual();
      final historico = await AssinaturaService.buscarHistorico();
      final consumo = await AssinaturaService.buscarConsumo();
      if (!mounted) return;

      final ativa = assinatura?['status']?.toString().toUpperCase() == 'ATIVA';
      final testeAtivo = ativa && assinatura?['testeGratuito'] == true;
      final fimTeste = DateTime.tryParse(
        assinatura?['dataVencimento']?.toString() ?? '',
      );

      setState(() {
        _planoAtual = ativa
            ? assinatura?['plano']?.toString().toUpperCase()
            : null;
        _testeAtivo = testeAtivo;
        _testeUtilizado = historico.any(
          (item) => item['testeGratuito'] == true,
        );
        _fimTeste = testeAtivo ? fimTeste : null;
        _consumo = consumo;
        _carregando = false;
      });
    } on AssinaturaException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _consumo = null;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível consultar sua assinatura.';
        _consumo = null;
        _carregando = false;
      });
    }
  }

  Future<void> _abrirGerenciamento() async {
    await context.push('/empresa/assinatura/gerenciamento');
    if (mounted) await _carregarAssinatura();
  }

  Future<void> _abrirPagamento(String nome, String preco) async {
    await context.push(
      '/empresa/pagamento',
      extra: <String, dynamic>{'plano': nome, 'precoMensal': preco},
    );

    if (mounted) await _carregarAssinatura();
  }

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  int? _numeroConsumo(String campo) {
    final valor = _consumo?[campo];
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '');
  }

  String _formatarNumero(int? valor) {
    if (valor == null) return '—';
    return valor.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
  }

  Widget _indicadorConsumo({
    required String titulo,
    required int? utilizados,
    required int? limite,
    required int? disponiveis,
    required IconData icone,
  }) {
    final theme = Theme.of(context);
    final proporcao = limite != null && limite > 0 && utilizados != null
        ? (utilizados / limite).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icone, size: 19, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text('${_formatarNumero(utilizados)} / ${_formatarNumero(limite)}'),
          ],
        ),
        const SizedBox(height: 9),
        LinearProgressIndicator(value: proporcao, minHeight: 7),
        const SizedBox(height: 6),
        Text(
          'Disponíveis: ${_formatarNumero(disponiveis)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _cartaoConsumo() {
    final theme = Theme.of(context);
    final emTeste = _consumo?['testeGratuito'] == true;
    final entregasUsadas = _numeroConsumo('entregasUtilizadasMes');
    final entregasLimite = _numeroConsumo('limiteEntregasMes');
    final entregasDisponiveis = _numeroConsumo('entregasDisponiveisMes');
    final entregadores = _numeroConsumo('entregadoresVinculados');
    final limiteEntregadores = _numeroConsumo('limiteEntregadores');
    final vagasDisponiveis = _numeroConsumo('vagasDisponiveis');
    final pendentes = _numeroConsumo('solicitacoesPendentes') ?? 0;
    final vagasOcupadas = _numeroConsumo('vagasOcupadas') ?? entregadores;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Consumo do plano',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              emTeste
                  ? 'Limite de entregas válido para os 14 dias completos do teste.'
                  : 'Entregas contabilizadas no período mensal atual.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            _indicadorConsumo(
              titulo: 'Entregas',
              utilizados: entregasUsadas,
              limite: entregasLimite,
              disponiveis: entregasDisponiveis,
              icone: Icons.inventory_2_outlined,
            ),
            const SizedBox(height: 20),
            _indicadorConsumo(
              titulo: 'Vagas de entregadores',
              utilizados: vagasOcupadas,
              limite: limiteEntregadores,
              disponiveis: vagasDisponiveis,
              icone: Icons.delivery_dining_outlined,
            ),
            const SizedBox(height: 8),
            Text(
              '$entregadores vinculados • $pendentes solicitações pendentes',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _iniciarTeste() async {
    if (_carregando || _ativandoTeste || _testeUtilizado ||
        _planoAtual != 'GRATUITO') {
      return;
    }

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

    setState(() => _ativandoTeste = true);

    try {
      await AssinaturaService.iniciarTesteEssencial();
      if (!mounted) return;
      await _carregarAssinatura();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teste Essencial ativado com sucesso!')),
      );
    } on AssinaturaException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensagem)),
      );
      await _carregarAssinatura();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível confirmar a ativação. Consulte sua assinatura.'),
        ),
      );
      await _carregarAssinatura();
    } finally {
      if (mounted) setState(() => _ativandoTeste = false);
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
            onPressed: _carregando || _ativandoTeste ? null : _carregarAssinatura,
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
                onPressed: _ativandoTeste ? null : _abrirGerenciamento,
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
                        onPressed: _carregarAssinatura,
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
            if (!_carregando && _erro == null && _consumo != null) ...[
              const SizedBox(height: 18),
              _cartaoConsumo(),
            ],
            const SizedBox(height: 18),
            _CartaoPlano(
              nome: 'Gratuito',
              preco: 'R\$ 0,00',
              entregadores: 1,
              entregasPorMes: 100,
              gratuito: true,
              planoAtual: _planoAtual == 'GRATUITO',
              verificando: _carregando || _ativandoTeste || _erro != null,
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
              verificando: _carregando || _ativandoTeste || _erro != null,
              onEscolher: () => _abrirPagamento('Essencial', 'R\$ 39,90'),
            ),
            const SizedBox(height: 14),
            _CartaoPlano(
              nome: 'Profissional',
              preco: 'R\$ 79,90',
              entregadores: 10,
              entregasPorMes: 5000,
              planoAtual: _planoAtual == 'PROFISSIONAL',
              verificando: _carregando || _ativandoTeste || _erro != null,
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
                        onPressed: _carregando || _erro != null ||
                                _ativandoTeste || _testeUtilizado ||
                                _planoAtual != 'GRATUITO'
                            ? null
                            : _iniciarTeste,
                        icon: _ativandoTeste
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_testeAtivo
                                ? Icons.check_circle_outline
                                : Icons.workspace_premium_outlined),
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
                        'Os preços e limites são provisórios. As regras de franquia foram implementadas no backend, mas ainda precisam de validação após o deploy. A integração de pagamentos ainda está em desenvolvimento.',
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
