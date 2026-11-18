import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/assinatura_service.dart';

class EntregadorPlanosPage extends StatefulWidget {
  const EntregadorPlanosPage({super.key});

  @override
  State<EntregadorPlanosPage> createState() => _EntregadorPlanosPageState();
}

class _EntregadorPlanosPageState extends State<EntregadorPlanosPage> {
  bool _carregando = true;
  String? _erro;
  String? _planoAtual;

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
      if (!mounted) return;
      setState(() {
        _planoAtual = assinatura?['plano']?.toString().toUpperCase();
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
        _erro = 'Não foi possível consultar sua assinatura.';
        _carregando = false;
      });
    }
  }

  Future<void> _abrirGerenciamento() async {
    await context.push('/entregador/assinatura/gerenciamento');
    if (!mounted) return;
    await _carregarAssinatura();
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
            onPressed: _carregando ? null : _carregarAssinatura,
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
                onPressed: _abrirGerenciamento,
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
                        onPressed: _carregarAssinatura,
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
                        'Os preços e limites são provisórios. A contratação dos planos pagos ainda não está disponível. Entregas atribuídas por empresas vinculadas não exigem assinatura pessoal.',
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

  const _CartaoPlanoEntregador({
    required this.nome,
    required this.preco,
    required this.beneficios,
    this.gratuito = false,
    this.destaque = false,
    this.planoAtual = false,
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
                onPressed: null,
                icon: Icon(
                  planoAtual
                      ? Icons.check_circle_outline
                      : gratuito
                      ? Icons.check_circle_outline
                      : Icons.lock_outline,
                ),
                label: Text(
                  planoAtual
                      ? 'Seu plano atual'
                      : gratuito
                      ? 'Plano gratuito'
                      : 'Disponível em breve',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
