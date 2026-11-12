import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

class SuportePage extends StatelessWidget {
  const SuportePage({super.key});

  static const String emailSuporte = 'entregueja1@gmail.com';

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
                  pergunta: 'Como faço para receber entregas?',
                  resposta:
                      'Após aceitar o vínculo com uma empresa, as entregas atribuídas a '
                      'você poderão ser consultadas na lista de entregas do aplicativo.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como cadastrar uma entrega?',
                  resposta:
                      'No painel da empresa, acesse a opção de cadastrar entrega,'
                      'preencha os dados solicitados e salve. Você pode vincular um '
                      'entregador durante o cadastro ou posteriormente.',
                ),

                faq(
                  context: context,
                  pergunta:
                      'Como funciona o vínculo entre empresa e entregador?',
                  resposta:
                      'A empresa envia uma solicitação de vínculo ao entregador. Ele pode '
                      'aceitar ou recusar a solicitação pelo aplicativo. A empresa pode '
                      'consultar seus entregadores vinculados.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como consultar o status de uma entrega?',
                  resposta:
                      'Acesse a lista de entregas para consultar os registros e seus '
                      'respectivos status. No painel da empresa, também é possível abrir '
                      'os detalhes de cada entrega.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como usar o QR Code?',
                  resposta:
                      'Na área de entregas do entregador, escolha a leitura de QR Code e '
                      'aponte a câmera para o código. O aplicativo tentará localizar os '
                      'dados correspondentes.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como visualizar e iniciar uma rota?',
                  resposta:
                      'No painel do entregador, abra o mapa para consultar as entregas e '
                      'a rota disponível. Quando desejar navegar, utilize a opção de '
                      'iniciar a rota no Google Maps.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como finalizar uma entrega?',
                  resposta:
                      'Abra os detalhes da entrega e escolha a opção de finalização. Siga '
                      'as etapas de registro solicitadas pelo aplicativo, incluindo foto '
                      'e localização quando necessário.',
                ),

                faq(
                  context: context,
                  pergunta: 'O que fazer se uma entrega não for realizada?',
                  resposta:
                      'Na finalização da entrega, utilize a opção de registrar a '
                      'tentativa sem sucesso e informe os dados solicitados. A empresa '
                      'poderá acompanhar o status atualizado.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como acompanhar as entregas pela empresa?',
                  resposta:
                      'No painel empresarial, acesse a lista de entregas e abra os '
                      'detalhes para consultar o andamento. Quando houver informações de '
                      'localização disponíveis, elas poderão ser exibidas no '
                      'acompanhamento.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como alterar as preferências de notificações?',
                  resposta:
                      'Abra as configurações e acesse Notificações para escolher quais '
                      'avisos deseja receber. As opções disponíveis podem variar entre '
                      'empresa e entregador.',
                ),

                faq(
                  context: context,
                  pergunta: 'Como entrar em contato com o suporte?',
                  resposta:
                      'Na tela de Suporte, toque em E-mail de suporte para abrir seu '
                      'aplicativo de e-mail e enviar uma mensagem para '
                      'entregueja1@gmail.com.',
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
                          'Entre em contato pelo e-mail de suporte.',
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
        ],
      ),
    );
  }
}
