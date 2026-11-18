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
        _planoAtual = assinatura != null && assinatura['status'] == 'ATIVA'
            ? assinatura['plano']?.toString().toUpperCase()
            : null;
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
    await context.push('/empresa/assinatura/gerenciamento');
    if (mounted) await _carregarAssinatura();
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
              'Um plano para cada etapa da sua empresa',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Compare os limites disponíveis e escolha a opção ideal para suas entregas.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _abrirGerenciamento,
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
            const SizedBox(height: 18),
            _CartaoPlano(
              nome: 'Gratuito',
              preco: 'R\$ 0,00',
              entregadores: 1,
              entregasPorDia: 20,
              gratuito: true,
              planoAtual: _planoAtual == 'GRATUITO',
              verificando: _carregando || _erro != null,
            ),
            const SizedBox(height: 14),
            _CartaoPlano(
              nome: 'Essencial',
              preco: 'R\$ 39,90',
              entregadores: 3,
              entregasPorDia: 50,
              destaque: true,
              planoAtual: _planoAtual == 'ESSENCIAL',
              verificando: _carregando || _erro != null,
            ),
            const SizedBox(height: 14),
            _CartaoPlano(
              nome: 'Profissional',
              preco: 'R\$ 79,90',
              entregadores: 10,
              entregasPorDia: 200,
              planoAtual: _planoAtual == 'PROFISSIONAL',
              verificando: _carregando || _erro != null,
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
                        'A contratação dos planos pagos estará disponível em breve. Os preços e limites apresentados são provisórios.',
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
  final int entregasPorDia;
  final bool gratuito;
  final bool destaque;
  final bool planoAtual;
  final bool verificando;

  const _CartaoPlano({
    required this.nome,
    required this.preco,
    required this.entregadores,
    required this.entregasPorDia,
    this.gratuito = false,
    this.destaque = false,
    this.planoAtual = false,
    this.verificando = false,
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
            _Beneficio(
              texto: entregadores == 1
                  ? '1 entregador vinculado'
                  : '$entregadores entregadores vinculados',
            ),
            const SizedBox(height: 12),
            _Beneficio(texto: '$entregasPorDia entregas por dia'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: verificando || planoAtual || gratuito
                    ? null
                    : () => context.push(
                        '/empresa/pagamento',
                        extra: <String, dynamic>{
                          'plano': nome,
                          'precoMensal': preco,
                        },
                      ),
                icon: Icon(
                  planoAtual || gratuito
                      ? Icons.check_circle_outline
                      : Icons.credit_card,
                ),
                label: Text(
                  planoAtual
                      ? 'Seu plano atual'
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
