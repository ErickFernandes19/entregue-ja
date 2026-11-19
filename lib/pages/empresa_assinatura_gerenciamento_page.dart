import 'package:flutter/material.dart';

import '../services/assinatura_service.dart';

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
      'entregasUtilizadasHoje',
      'limiteEntregasDia',
      'entregasDisponiveisHoje',
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

    final entregas = _numero(consumo['entregasUtilizadasHoje']);
    final limiteEntregas = _numero(consumo['limiteEntregasDia']);
    final ocupadas = _numero(consumo['vagasOcupadas']);
    final limiteVagas = _numero(consumo['limiteEntregadores']);
    final vinculados = _numero(consumo['entregadoresVinculados']);
    final pendentes = _numero(consumo['solicitacoesPendentes']);
    final disponiveis = _numero(consumo['vagasDisponiveis']);
    final entregasRestantes = _numero(consumo['entregasDisponiveisHoje']);
    final dataReferencia = consumo['dataReferencia']?.toString();

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
              titulo: 'Entregas criadas hoje',
              utilizado: entregas,
              limite: limiteEntregas,
              detalhe:
                  '$entregasRestantes entregas disponíveis hoje. Entregas canceladas também contam.',
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
                  const ListTile(
                    leading: Icon(Icons.autorenew),
                    title: Text('Renovação automática'),
                    subtitle: Text('Gerenciamento ainda não disponível'),
                    trailing: Icon(Icons.lock_outline),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  const ListTile(
                    leading: Icon(Icons.credit_card_outlined),
                    title: Text('Forma de pagamento'),
                    subtitle: Text('Disponível após integração de pagamentos'),
                    trailing: Icon(Icons.lock_outline),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  const ListTile(
                    leading: Icon(Icons.cancel_outlined),
                    title: Text('Cancelar assinatura'),
                    subtitle: Text('Cancelamento ainda não disponível'),
                    trailing: Icon(Icons.lock_outline),
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
                        'A contratação e o gerenciamento de assinaturas ainda não estão habilitados. Nenhuma cobrança, renovação ou cancelamento é realizado nesta versão.',
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
