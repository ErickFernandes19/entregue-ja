import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class EmpresaConfiguracoesPage extends StatelessWidget {
  const EmpresaConfiguracoesPage({super.key});

  String textoTema(ThemeMode modo) {
    switch (modo) {
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.dark:
        return 'Escuro';
      case ThemeMode.system:
        return 'Usar configuração do sistema';
    }
  }

  IconData iconeTema(ThemeMode modo) {
    switch (modo) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.settings_brightness;
    }
  }

  Future<void> abrirAparencia(BuildContext context) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Consumer<ThemeProvider>(
          builder: (context, provider, child) {
            final theme = Theme.of(context);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(
                        'Aparência',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      groupValue: provider.themeMode,
                      secondary: const Icon(Icons.settings_brightness),
                      title: const Text('Sistema'),
                      subtitle: const Text('Segue a configuração do celular'),
                      onChanged: (modo) async {
                        if (modo == null) return;

                        await themeProvider.alterarTema(modo);
                      },
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      groupValue: provider.themeMode,
                      secondary: const Icon(Icons.light_mode),
                      title: const Text('Claro'),
                      subtitle: const Text('Sempre usar o modo claro'),
                      onChanged: (modo) async {
                        if (modo == null) return;

                        await themeProvider.alterarTema(modo);
                      },
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      groupValue: provider.themeMode,
                      secondary: const Icon(Icons.dark_mode),
                      title: const Text('Escuro'),
                      subtitle: const Text('Sempre usar o modo escuro'),
                      onChanged: (modo) async {
                        if (modo == null) return;

                        await themeProvider.alterarTema(modo);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget opcao({
    required BuildContext context,
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: ListTile(
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
          Icons.arrow_forward_ios,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget botaoSair(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.error.withOpacity(0.20)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.error.withOpacity(0.14),
          child: Icon(Icons.logout, color: theme.colorScheme.error),
        ),
        title: Text(
          'Sair',
          style: TextStyle(
            color: theme.colorScheme.onErrorContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'Encerrar sessão da empresa',
          style: TextStyle(
            color: theme.colorScheme.onErrorContainer.withOpacity(0.80),
          ),
        ),
        onTap: () async {
          await EmpresaService.logoutEmpresa();

          if (!context.mounted) return;

          context.go('/selecionar');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações da Empresa'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Conta',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 12),

          opcao(
            context: context,
            icon: Icons.business,
            titulo: 'Dados da Empresa',
            subtitulo: 'Nome, e-mail e informações cadastrais',
            color: AppColors.primary,
            onTap: () {
              context.push('/empresa/perfil');
            },
          ),

          opcao(
            context: context,
            icon: Icons.groups,
            titulo: 'Meus Entregadores',
            subtitulo: 'Ver entregadores vinculados',
            color: AppColors.success,
            onTap: () {
              context.push('/empresa/entregadores');
            },
          ),

          opcao(
            context: context,
            icon: Icons.person_add,
            titulo: 'Vincular Entregador',
            subtitulo: 'Enviar solicitação de vínculo',
            color: Colors.orange,
            onTap: () {
              context.push('/empresa/vincular-entregador');
            },
          ),

          const SizedBox(height: 14),

          Text(
            'Entregas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 12),

          opcao(
            context: context,
            icon: Icons.inventory,
            titulo: 'Histórico de Entregas',
            subtitulo: 'Ver entregas cadastradas e status',
            color: Colors.deepPurple,
            onTap: () {
              context.push('/empresa/entregas');
            },
          ),

          const SizedBox(height: 14),

          Text(
            'Preferências',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 12),

          opcao(
            context: context,
            icon: Icons.notifications,
            titulo: 'Notificações',
            subtitulo: 'Avisos e atualizações do sistema',
            color: AppColors.warning,
            onTap: () {
              context.push('/empresa/notificacoes');
            },
          ),

          opcao(
            context: context,
            icon: iconeTema(themeProvider.themeMode),
            titulo: 'Aparência',
            subtitulo: textoTema(themeProvider.themeMode),
            color: Colors.indigo,
            onTap: () {
              abrirAparencia(context);
            },
          ),

          const SizedBox(height: 14),

          Text(
            'Ajuda',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 12),

          opcao(
            context: context,
            icon: Icons.support_agent,
            titulo: 'Suporte',
            subtitulo: 'Ajuda e atendimento',
            color: Colors.deepPurple,
            onTap: () {
              context.push('/empresa/suporte');
            },
          ),

          opcao(
            context: context,
            icon: Icons.info,
            titulo: 'Sobre o App',
            subtitulo: 'Informações do Entregue Já',
            color: AppColors.primary,
            onTap: () {
              context.push('/empresa/sobre');
            },
          ),

          botaoSair(context),
        ],
      ),
    );
  }
}
