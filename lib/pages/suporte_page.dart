import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

class SuportePage extends StatelessWidget {
  const SuportePage({super.key});

  static const String emailSuporte = 'suporte@entregueja.com';
  static const String telefoneSuporte = '44999999999';

  Future<void> abrirEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: emailSuporte,
      queryParameters: {'subject': 'Suporte - Entregue Já'},
    );

    final abriu = await launchUrl(uri);

    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o aplicativo de e-mail.'),
        ),
      );
    }
  }

  Future<void> abrirTelefone(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: telefoneSuporte);

    final abriu = await launchUrl(uri);

    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o aplicativo de telefone.'),
        ),
      );
    }
  }

  void abrirCentralAjuda(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  'Central de ajuda',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Encontre respostas para dúvidas frequentes.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),

                const SizedBox(height: 22),

                faq(
                  context: context,
                  pergunta: 'Como recebo uma entrega?',
                  resposta:
                      'Quando uma empresa cadastrar uma entrega para você, '
                      'ela aparecerá na sua lista de entregas.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como uso o QR Code?',
                  resposta:
                      'Na tela de entregas, toque em QR Code e aponte a '
                      'câmera para o código da entrega. O aplicativo buscará '
                      'os dados correspondentes.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como iniciar uma rota?',
                  resposta:
                      'Abra a opção Mapa, confira as entregas pendentes e '
                      'toque em Iniciar. O aplicativo abrirá a rota no '
                      'Google Maps.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como finalizar uma entrega?',
                  resposta:
                      'Na entrega desejada, toque em Finalizar entrega. '
                      'Será necessário registrar uma foto e a localização '
                      'para concluir ou informar uma tentativa sem sucesso.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como alterar meu veículo?',
                  resposta:
                      'Abra Configurações, depois Veículo e Combustível. '
                      'Escolha o veículo e informe os dados desejados.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como funciona o vínculo com uma empresa?',
                  resposta:
                      'A empresa envia uma solicitação para o e-mail do '
                      'entregador. O entregador pode aceitar ou recusar a '
                      'solicitação nas configurações.',
                ),

                faq(
                  context: context,
                  pergunta: 'A empresa consegue acompanhar as entregas?',
                  resposta:
                      'Sim. A empresa consegue visualizar as entregas '
                      'cadastradas e acompanhar seus respectivos status.',
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.18),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.support_agent, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Não encontrou o que precisava? '
                          'Entre em contato pelo e-mail ou telefone.',
                          style: TextStyle(color: theme.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget faq({
    required BuildContext context,
    required String pergunta,
    required String resposta,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.12),
          child: const Icon(Icons.help_outline, color: AppColors.primary),
        ),
        title: Text(
          pergunta,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                resposta,
                style: TextStyle(
                  height: 1.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget opcaoSuporte({
    required BuildContext context,
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              theme.brightness == Brightness.dark ? 0.16 : 0.04,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.14),
          child: Icon(icon, color: color),
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitulo,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Suporte'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Como podemos ajudar?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Encontre ajuda ou entre em contato com o suporte.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 22),

          opcaoSuporte(
            context: context,
            icon: Icons.help_outline,
            titulo: 'Central de ajuda',
            subtitulo: 'Dúvidas frequentes sobre o aplicativo',
            color: AppColors.primary,
            onTap: () {
              abrirCentralAjuda(context);
            },
          ),

          opcaoSuporte(
            context: context,
            icon: Icons.email_outlined,
            titulo: 'E-mail de suporte',
            subtitulo: emailSuporte,
            color: Colors.deepPurple,
            onTap: () {
              abrirEmail(context);
            },
          ),

          opcaoSuporte(
            context: context,
            icon: Icons.phone_outlined,
            titulo: 'Telefone',
            subtitulo: '(44) 99999-9999',
            color: AppColors.success,
            onTap: () {
              abrirTelefone(context);
            },
          ),
        ],
      ),
    );
  }
}
