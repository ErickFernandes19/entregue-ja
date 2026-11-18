import 'package:flutter/material.dart';

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

  void _mostrarIndisponibilidade() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pagamentos em breve'),
        content: const Text(
          'A integração de pagamentos ainda não está disponível. '
          'Nenhuma cobrança foi realizada e seu plano não foi alterado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isPix = _forma == _FormaPagamento.pix;

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
                          'Cobrança mensal após a ativação do serviço de pagamentos.',
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
                  child: Column(
                    children: [
                      RadioListTile<_FormaPagamento>(
                        value: _FormaPagamento.pix,
                        groupValue: _forma,
                        onChanged: (value) {
                          if (value != null) setState(() => _forma = value);
                        },
                        title: const Text('Pix'),
                        subtitle: const Text(
                          'Pagamento por QR Code ou código copia e cola',
                        ),
                        secondary: const Icon(Icons.qr_code_2),
                      ),
                      const Divider(height: 1),
                      RadioListTile<_FormaPagamento>(
                        value: _FormaPagamento.cartao,
                        groupValue: _forma,
                        onChanged: (value) {
                          if (value != null) setState(() => _forma = value);
                        },
                        title: const Text('Cartão de crédito'),
                        subtitle: const Text(
                          'Pagamento com cartão via provedor seguro',
                        ),
                        secondary: const Icon(Icons.credit_card),
                      ),
                    ],
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
                              ? 'O QR Code Pix será gerado pelo provedor de pagamentos quando a integração estiver disponível.'
                              : 'Os dados do cartão serão informados em um ambiente seguro do provedor quando a integração estiver disponível.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _mostrarIndisponibilidade,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(
                    isPix ? 'Continuar com Pix' : 'Continuar com cartão',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Demonstração de interface. Nenhuma cobrança ou alteração de plano será realizada.',
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
