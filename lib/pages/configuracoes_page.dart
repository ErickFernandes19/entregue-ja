import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  Map<String, dynamic>? vinculoPendente;

  @override
  void initState() {
    super.initState();
    carregarVinculoPendente();
  }

  Future<void> carregarVinculoPendente() async {
    final resultado = await AuthService.buscarVinculoPendente();

    if (!mounted) return;

    setState(() {
      vinculoPendente = resultado;
    });
  }

  Future<void> aceitarVinculo() async {
    final sucesso = await AuthService.aceitarVinculo();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sucesso ? 'Vínculo aceito com sucesso' : 'Erro ao aceitar vínculo',
        ),
      ),
    );

    if (sucesso) {
      carregarVinculoPendente();
    }
  }

  Future<void> recusarVinculo() async {
    final sucesso = await AuthService.recusarVinculo();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sucesso ? 'Vínculo recusado' : 'Erro ao recusar vínculo'),
      ),
    );

    if (sucesso) {
      carregarVinculoPendente();
    }
  }

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

  Future<void> abrirAparencia() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Consumer<ThemeProvider>(
          builder: (context, provider, child) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(
                        'Aparência',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
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

  Widget header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 46, 18, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              context.pop();
            },
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configurações',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Preferências do entregador.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white,
              child: Icon(Icons.settings, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget opcaoMenu({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required Color color,
    required VoidCallback onTap,
  }) {
    final tema = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tema.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: tema.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitulo,
          style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget cardVinculoPendente() {
    final possuiVinculo = vinculoPendente?['possuiVinculo'] == true;

    if (!possuiVinculo) {
      return const SizedBox();
    }

    final empresa = vinculoPendente?['empresa'] ?? 'Empresa';

    final email = vinculoPendente?['email'] ?? '';

    final tema = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tema.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.blue.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.12),
                child: const Icon(Icons.business, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                'Solicitação de vínculo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: tema.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Empresa: $empresa',
            style: TextStyle(color: tema.colorScheme.onSurface),
          ),
          if (email.toString().isNotEmpty)
            Text(
              'E-mail: $email',
              style: TextStyle(color: tema.colorScheme.onSurface),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: aceitarVinculo,
                  icon: const Icon(Icons.check),
                  label: const Text('Aceitar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: recusarVinculo,
                  icon: const Icon(Icons.close),
                  label: const Text('Recusar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget botaoSair() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.error.withOpacity(0.15),
          child: Icon(Icons.logout, color: colorScheme.error),
        ),
        title: Text(
          'Sair',
          style: TextStyle(
            color: colorScheme.onErrorContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'Encerrar sessão do entregador',
          style: TextStyle(color: colorScheme.onErrorContainer),
        ),
        onTap: () async {
          await AuthService.logout();

          if (!context.mounted) return;

          context.go('/selecionar');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      body: Column(
        children: [
          header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                cardVinculoPendente(),

                opcaoMenu(
                  icon: Icons.directions_car,
                  titulo: 'Veículo e Combustível',
                  subtitulo: 'Capacidade, consumo e preço do combustível',
                  color: AppColors.primary,
                  onTap: () {
                    context.push('/entregador/configuracoes/veiculo');
                  },
                ),

                opcaoMenu(
                  icon: Icons.notifications,
                  titulo: 'Notificações',
                  subtitulo: 'Ativar ou desativar alertas',
                  color: Colors.orange,
                  onTap: () {
                    context.push('/entregador/notificacoes');
                  },
                ),

                opcaoMenu(
                  icon: iconeTema(themeProvider.themeMode),
                  titulo: 'Aparência',
                  subtitulo: textoTema(themeProvider.themeMode),
                  color: Colors.indigo,
                  onTap: abrirAparencia,
                ),

                opcaoMenu(
                  icon: Icons.article,
                  titulo: 'Relatórios',
                  subtitulo: 'Veja seu resumo de entregas',
                  color: AppColors.primary,
                  onTap: () {
                    context.push('/entregador/relatorios');
                  },
                ),

                opcaoMenu(
                  icon: Icons.support_agent,
                  titulo: 'Suporte',
                  subtitulo: 'Ajuda e atendimento',
                  color: Colors.deepPurple,
                  onTap: () {
                    context.push('/entregador/suporte');
                  },
                ),

                opcaoMenu(
                  icon: Icons.info,
                  titulo: 'Sobre o App',
                  subtitulo: 'Informações do Entregue Já',
                  color: AppColors.success,
                  onTap: () {
                    context.push('/entregador/sobre');
                  },
                ),

                const SizedBox(height: 8),

                botaoSair(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
