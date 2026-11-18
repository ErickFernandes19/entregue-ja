import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum StatusPagamento { aprovado, pendente, naoConcluido }

class EmpresaPagamentoResultadoPage extends StatelessWidget {
  final StatusPagamento status;
  final String plano;
  final String valor;
  final String? formaPagamento;

  const EmpresaPagamentoResultadoPage({
    super.key,
    required this.status,
    required this.plano,
    required this.valor,
    this.formaPagamento,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final aprovado = status == StatusPagamento.aprovado;
    final pendente = status == StatusPagamento.pendente;
    final titulo = aprovado
        ? 'Pagamento confirmado'
        : pendente
        ? 'Pagamento pendente'
        : 'Pagamento não concluído';
    final descricao = aprovado
        ? 'O pagamento foi confirmado pelo serviço de pagamentos. Consulte os detalhes da sua assinatura.'
        : pendente
        ? 'O pagamento ainda está aguardando confirmação. Seu plano só será atualizado após a confirmação do serviço de pagamentos.'
        : 'Não foi possível concluir o pagamento. Nenhuma ativação de plano foi realizada.';
    final icone = aprovado
        ? Icons.check_circle_outline
        : pendente
        ? Icons.schedule_outlined
        : Icons.error_outline;
    final cor = aprovado
        ? colors.primary
        : pendente
        ? colors.tertiary
        : colors.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado do pagamento'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            shrinkWrap: true,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(icone, size: 72, color: cor),
                      const SizedBox(height: 16),
                      Text(
                        titulo,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        descricao,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 12),
                      _LinhaDetalhe(rotulo: 'Plano', valor: plano),
                      const SizedBox(height: 12),
                      _LinhaDetalhe(rotulo: 'Mensalidade', valor: valor),
                      if (formaPagamento != null &&
                          formaPagamento!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _LinhaDetalhe(
                          rotulo: 'Forma de pagamento',
                          valor: formaPagamento!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.go('/empresa/planos'),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Voltar aos planos'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.go('/empresa/inicio'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Ir para o início'),
              ),
              const SizedBox(height: 16),
              Text(
                'Esta tela apresenta o resultado recebido do serviço de pagamentos. A confirmação e a ativação da assinatura dependem da integração com o provedor e da validação pelo servidor.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinhaDetalhe extends StatelessWidget {
  final String rotulo;
  final String valor;

  const _LinhaDetalhe({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(rotulo)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
