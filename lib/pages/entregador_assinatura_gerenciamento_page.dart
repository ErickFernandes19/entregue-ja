import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assinatura_service.dart';

class EntregadorAssinaturaGerenciamentoPage extends StatefulWidget {
  const EntregadorAssinaturaGerenciamentoPage({super.key});

  @override
  State<EntregadorAssinaturaGerenciamentoPage> createState() =>
      _EntregadorAssinaturaGerenciamentoPageState();
}

class _EntregadorAssinaturaGerenciamentoPageState
    extends State<EntregadorAssinaturaGerenciamentoPage> {
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

  int? _inteiro(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num && valor.isFinite && valor == valor.roundToDouble()) {
      return valor.toInt();
    }
    if (valor is String) return int.tryParse(valor);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consumo = _consumo;
    final plano = _assinatura?['plano']?.toString();
    final consumoValido =
        consumo != null && consumo['tipoConta'] == 'ENTREGADOR';
    final ilimitado = consumoValido && consumo['entregasIlimitadas'] == true;
    final usadas = consumoValido
        ? _inteiro(consumo['entregasUtilizadasHoje'])
        : null;
    final limite = consumoValido
        ? _inteiro(consumo['limiteEntregasDia'])
        : null;
    final restantes = consumoValido
        ? _inteiro(consumo['entregasDisponiveisHoje'])
        : null;
    final consumoCompleto =
        consumoValido &&
        usadas != null &&
        usadas >= 0 &&
        consumo['entregasIlimitadas'] is bool &&
        (ilimitado ||
            (limite != null &&
                limite > 0 &&
                restantes != null &&
                restantes >= 0));

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
              'Consulte as opções disponíveis para suas entregas independentes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assinatura atual',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                        'Ainda não há uma assinatura ativa registrada para esta conta.',
                      )
                    else ...[
                      Text('Plano: ${_rotulo(plano)}'),
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
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.push('/entregador/planos'),
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label: const Text('Ver planos disponíveis'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consumo de entregas independentes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_carregando)
                      const Center(child: CircularProgressIndicator())
                    else if (_erro != null)
                      const Text('Consumo indisponível no momento.')
                    else if (!consumoCompleto)
                      const Text(
                        'Os dados de consumo estão indisponíveis ou incompletos.',
                      )
                    else ...[
                      Text('Utilizadas hoje: $usadas'),
                      const SizedBox(height: 8),
                      Text(
                        'Limite diário: ${ilimitado ? 'Ilimitado' : limite.toString()}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Restantes hoje: ${ilimitado ? 'Ilimitadas' : restantes.toString()}',
                      ),
                      if (!ilimitado && limite != null && limite > 0) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: (usadas / limite).clamp(0.0, 1.0),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${((usadas / limite) * 100).clamp(0.0, 100.0).toStringAsFixed(0)}% do limite diário utilizado',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'As entregas atribuídas por empresas vinculadas não utilizam sua franquia pessoal.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Histórico de assinaturas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_carregando)
                      const Center(child: CircularProgressIndicator())
                    else if (_erro != null)
                      const Text('Histórico indisponível no momento.')
                    else if (_historico.isEmpty)
                      const Text('Nenhuma assinatura disponível para consulta.')
                    else
                      ..._historico.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_rotulo(item['plano']?.toString())),
                          subtitle: Text(
                            'Status: ${_rotulo(item['status']?.toString())}\n'
                            'Início: ${_data(item['dataInicio'])}',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.autorenew),
                    title: Text('Renovação automática'),
                    subtitle: Text('Gerenciamento ainda não disponível.'),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.credit_card_outlined),
                    title: Text('Forma de pagamento'),
                    subtitle: Text('Disponível após integração de pagamentos.'),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.cancel_outlined),
                    title: Text('Cancelar assinatura'),
                    subtitle: Text('Cancelamento ainda não disponível.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'A contratação e o gerenciamento de assinaturas ainda não estão habilitados. Esta tela não realiza cobranças.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
