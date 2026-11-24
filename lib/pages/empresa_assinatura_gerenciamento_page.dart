import 'package:flutter/material.dart';

import '../services/assinatura_service.dart';
import '../services/pagamento_assinatura_service.dart';

class EmpresaAssinaturaGerenciamentoPage extends StatefulWidget {
  const EmpresaAssinaturaGerenciamentoPage({super.key});

  @override
  State<EmpresaAssinaturaGerenciamentoPage> createState() =>
      _EmpresaAssinaturaGerenciamentoPageState();
}

class _EmpresaAssinaturaGerenciamentoPageState
    extends State<EmpresaAssinaturaGerenciamentoPage> {
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic>? _assinatura;
  Map<String, dynamic>? _consumo;
  List<Map<String, dynamic>> _historico = [];
  List<Map<String, dynamic>> _recorrentes = [];
  bool _cancelando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final resultados = await Future.wait<dynamic>([
        AssinaturaService.buscarAtual(),
        AssinaturaService.buscarHistorico(),
        AssinaturaService.buscarConsumo(),
      ]);

      if (!mounted) return;

      setState(() {
        _assinatura = resultados[0] as Map<String, dynamic>?;
        _historico = resultados[1] as List<Map<String, dynamic>>;
        _consumo = resultados[2] as Map<String, dynamic>;

        _carregando = false;
      });
      try {
        final recorrentes =
            await PagamentoAssinaturaService.listarAssinaturasRecorrentes();
        if (mounted) setState(() => _recorrentes = recorrentes);
      } catch (_) {
        if (mounted) setState(() => _recorrentes = []);
      }
    } on AssinaturaException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os dados da assinatura.';
        _carregando = false;
      });
    }
  }

  Future<void> _cancelarRecorrente(Map<String, dynamic> assinatura) async {
    if (_cancelando) return;
    final id = int.tryParse(assinatura['assinaturaId']?.toString() ?? '');
    if (id == null || id <= 0) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Cancelar assinatura?'),
        content: const Text(
          'O cancelamento será solicitado ao Mercado Pago. Confira o resultado antes de tentar outra contratação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    setState(() => _cancelando = true);
    try {
      await PagamentoAssinaturaService.cancelarAssinaturaRecorrente(
        assinaturaId: id,
      );
      if (!mounted) return;
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitação concluída. Confira o status da assinatura.',
          ),
        ),
      );
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível confirmar o cancelamento: $erro'),
        ),
      );
      await _carregar();
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  Future<void> _mostrarRenovacao() async {
    final ativas = _recorrentes.where((item) {
      final status = item['status']?.toString().toUpperCase();
      return status == 'PENDENTE' ||
          status == 'AUTORIZADA' ||
          status == 'PAUSADA';
    }).toList();
    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Renovação automática'),
        content: Text(
          ativas.isEmpty
              ? 'Não há uma assinatura recorrente em andamento registrada nesta conta. Consulte os planos para contratar uma assinatura.'
              : 'Você possui ${ativas.length} assinatura(s) recorrente(s) em andamento. A renovação depende do status da cobrança no Mercado Pago. Para interromper novas cobranças, utilize Cancelar assinatura.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarFormaPagamento() async {
    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Forma de pagamento'),
        content: const Text(
          'O pagamento por Pix é realizado por cobrança individual. Para assinaturas recorrentes, a autorização do cartão acontece no ambiente seguro do Mercado Pago. Nenhum dado completo do cartão é armazenado nesta tela. A troca de cartão de uma assinatura existente ainda depende de suporte do serviço de pagamentos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _selecionarCancelamento() async {
    final cancelaveis = _recorrentes.where((item) {
      final status = item['status']?.toString().toUpperCase();
      return status == 'PENDENTE' ||
          status == 'AUTORIZADA' ||
          status == 'PAUSADA';
    }).toList();
    if (cancelaveis.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: const Text('Cancelar assinatura'),
          content: const Text(
            'Não há assinaturas recorrentes em andamento para cancelar nesta conta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contexto),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      return;
    }
    final escolhida = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Cancelar assinatura'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: cancelaveis.map((item) {
              return ListTile(
                title: Text('Assinatura nº ${item['assinaturaId'] ?? '-'}'),
                subtitle: Text('Status: ${item['status'] ?? 'Não informado'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(contexto, item),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto),
            child: const Text('Voltar'),
          ),
        ],
      ),
    );
    if (escolhida != null && mounted) {
      await _cancelarRecorrente(escolhida);
    }
  }

  Widget _painelRecorrentes() {
    final itens = _recorrentes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assinaturas recorrentes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Center(child: CircularProgressIndicator())
            else if (_erro != null)
              const Text(
                'Não foi possível consultar as assinaturas recorrentes.',
              )
            else if (itens.isEmpty)
              const Text('Nenhuma assinatura recorrente encontrada.')
            else
              ...itens.map((item) {
                final status =
                    item['status']?.toString().toUpperCase() ?? 'DESCONHECIDO';
                final cancelavel =
                    status == 'PENDENTE' ||
                    status == 'AUTORIZADA' ||
                    status == 'PAUSADA';
                return Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Assinatura nº ${item['assinaturaId'] ?? '-'}',
                      ),
                      subtitle: Text('Status: $status'),
                      trailing: cancelavel
                          ? TextButton(
                              onPressed: _cancelando || _carregando
                                  ? null
                                  : () => _cancelarRecorrente(item),
                              child: const Text('Cancelar'),
                            )
                          : null,
                    ),
                    const Divider(height: 1),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  String _rotulo(String? valor) {
    switch (valor) {
      case 'GRATUITO':
        return 'Gratuito';
      case 'ESSENCIAL':
        return 'Essencial';
      case 'PROFISSIONAL':
        return 'Profissional';
      case 'ATIVA':
        return 'Ativa';
      case 'PENDENTE':
        return 'Pendente';
      case 'CANCELADA':
        return 'Cancelada';
      case 'EXPIRADA':
        return 'Expirada';
      default:
        return valor?.isNotEmpty == true ? valor! : 'Não informado';
    }
  }

  String _data(dynamic valor) {
    if (valor == null) return 'Não informada';
    final data = DateTime.tryParse(valor.toString());
    if (data == null) return 'Não informada';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  int _numero(dynamic valor) {
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  Widget _indicador({
    required String titulo,
    required int utilizado,
    required int limite,
    required String detalhe,
  }) {
    final cores = Theme.of(context).colorScheme;
    final progresso = limite > 0 ? (utilizado / limite).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text('$utilizado / $limite'),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: progresso,
          minHeight: 9,
          borderRadius: BorderRadius.circular(10),
          color: utilizado >= limite ? cores.error : cores.primary,
        ),
        const SizedBox(height: 8),
        Text(detalhe, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _painelConsumo() {
    final consumo = _consumo;
    if (consumo == null || consumo['tipoConta'] != 'EMPRESA') {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Os dados de consumo da empresa não estão disponíveis.'),
        ),
      );
    }

    const camposObrigatorios = [
      'entregasUtilizadasPeriodo',
      'limiteEntregasPeriodo',
      'entregasDisponiveisPeriodo',
      'vagasOcupadas',
      'limiteEntregadores',
      'entregadoresVinculados',
      'solicitacoesPendentes',
      'vagasDisponiveis',
    ];

    final dadosValidos = camposObrigatorios.every((campo) {
      final valor = consumo[campo];
      return valor is num || int.tryParse(valor?.toString() ?? '') != null;
    });

    if (!dadosValidos) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Os indicadores de consumo estão indisponíveis no momento.',
          ),
        ),
      );
    }

    final entregas = _numero(consumo['entregasUtilizadasPeriodo']);
    final limiteEntregas = _numero(consumo['limiteEntregasPeriodo']);
    final ocupadas = _numero(consumo['vagasOcupadas']);
    final limiteVagas = _numero(consumo['limiteEntregadores']);
    final vinculados = _numero(consumo['entregadoresVinculados']);
    final pendentes = _numero(consumo['solicitacoesPendentes']);
    final disponiveis = _numero(consumo['vagasDisponiveis']);
    final entregasRestantes = _numero(consumo['entregasDisponiveisPeriodo']);
    final dataReferencia = consumo['dataReferencia']?.toString();
    final emTeste = consumo['periodo']?.toString() == 'TESTE';
    final periodo = emTeste ? 'período de teste' : 'mês';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Consumo do plano',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (dataReferencia != null) ...[
              const SizedBox(height: 6),
              Text(
                'Referência: $dataReferencia',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 20),
            _indicador(
              titulo: emTeste
                  ? 'Entregas no período de teste'
                  : 'Entregas no mês',
              utilizado: entregas,
              limite: limiteEntregas,
              detalhe:
                  '$entregasRestantes entregas disponíveis no $periodo. Entregas canceladas também contam.',
            ),
            const SizedBox(height: 24),
            _indicador(
              titulo: 'Vagas de entregadores ocupadas',
              utilizado: ocupadas,
              limite: limiteVagas,
              detalhe:
                  '$vinculados vinculados • $pendentes solicitações pendentes • $disponiveis vagas disponíveis',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha assinatura'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _carregando ? null : _carregar,
            tooltip: 'Atualizar assinatura',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Gerencie seu plano',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Consulte as informações disponíveis sobre sua assinatura.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.workspace_premium_outlined,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Plano atual',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_carregando)
                      const Center(child: CircularProgressIndicator())
                    else if (_erro != null) ...[
                      Text(_erro!),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _carregar,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ] else if (_assinatura == null)
                      const Text(
                        'Ainda não há uma assinatura ativa registrada para esta empresa.',
                      )
                    else ...[
                      Text(
                        'Plano: ${_rotulo(_assinatura!['plano']?.toString())}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Status: ${_rotulo(_assinatura!['status']?.toString())}',
                      ),
                      const SizedBox(height: 6),
                      Text('Início: ${_data(_assinatura!['dataInicio'])}'),
                      const SizedBox(height: 6),
                      Text(
                        'Vencimento: ${_data(_assinatura!['dataVencimento'])}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (!_carregando && _erro == null) ...[
              _painelConsumo(),
              const SizedBox(height: 18),
            ],
            Text(
              'Histórico de assinaturas',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: _carregando
                    ? const Center(child: CircularProgressIndicator())
                    : _erro != null
                    ? Text(
                        'Histórico indisponível no momento.',
                        style: theme.textTheme.bodyMedium,
                      )
                    : _historico.isEmpty
                    ? Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 44,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhuma assinatura disponível para consulta.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      )
                    : Column(
                        children: _historico.map((item) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_rotulo(item['plano']?.toString())),
                            subtitle: Text(
                              'Status: ${_rotulo(item['status']?.toString())}\n'
                              'Início: ${_data(item['dataInicio'])}',
                            ),
                            isThreeLine: true,
                          );
                        }).toList(),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            _painelRecorrentes(),
            const SizedBox(height: 18),
            Text(
              'Gerenciamento',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Alterar plano'),
                    subtitle: const Text('Comparar os planos disponíveis'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  ListTile(
                    leading: const Icon(Icons.autorenew),
                    title: const Text('Renovação automática'),
                    subtitle: const Text('Consultar situação da renovação'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _carregando ? null : _mostrarRenovacao,
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  ListTile(
                    leading: const Icon(Icons.credit_card_outlined),
                    title: const Text('Forma de pagamento'),
                    subtitle: const Text('Consultar as opções de cobrança'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _mostrarFormaPagamento,
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  ListTile(
                    leading: const Icon(Icons.cancel_outlined),
                    title: const Text('Cancelar assinatura'),
                    subtitle: const Text(
                      'Selecionar uma assinatura recorrente',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _carregando || _cancelando
                        ? null
                        : _selecionarCancelamento,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: colors.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'O status e as operações de cobrança são confirmados pelo servidor. Uma solicitação de cancelamento só é efetivada após confirmação do serviço de pagamentos.',
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
