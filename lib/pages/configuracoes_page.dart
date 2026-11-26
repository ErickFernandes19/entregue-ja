import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  Map<String, dynamic>? vinculoPendente;
  bool _carregandoVinculo = false;
  bool _alterandoVinculo = false;
  bool _alterandoTema = false;
  bool _saindo = false;

  @override
  void initState() {
    super.initState();
    carregarVinculoPendente();
  }

  void _mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> carregarVinculoPendente() async {
    if (_carregandoVinculo || _alterandoVinculo || _saindo) return;
    _carregandoVinculo = true;

    try {
      final resultado = await AuthService.buscarVinculoPendente(
        lancarErro: true,
      );

      if (resultado == null || resultado['possuiVinculo'] is! bool) {
        throw const FormatException('Resposta inválida');
      }

      if (!mounted || _saindo) return;
      setState(() => vinculoPendente = resultado);
    } catch (e) {
      if (!mounted || _saindo) return;
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível consultar a solicitação de vínculo.',
        ),
      );
    } finally {
      _carregandoVinculo = false;
    }
  }

  Future<void> aceitarVinculo() => _responderVinculo(aceitar: true);

  Future<void> recusarVinculo() => _responderVinculo(aceitar: false);

  Future<void> _responderVinculo({required bool aceitar}) async {
    if (_alterandoVinculo || _carregandoVinculo || _saindo || !mounted) {
      return;
    }
    if (vinculoPendente?['possuiVinculo'] != true) return;

    _alterandoVinculo = true;
    final mensagemPadrao = aceitar
        ? 'Não foi possível aceitar o vínculo. Tente novamente.'
        : 'Não foi possível recusar o vínculo. Tente novamente.';

    try {
      final sucesso = aceitar
          ? await AuthService.aceitarVinculo(lancarErro: true)
          : await AuthService.recusarVinculo(lancarErro: true);

      if (!sucesso) throw ApiException(mensagemPadrao);
      if (!mounted) return;

      setState(() => vinculoPendente = null);
      _mostrarMensagem(
        aceitar ? 'Vínculo aceito com sucesso' : 'Vínculo recusado',
      );
    } catch (e) {
      if (!mounted) return;
      _mostrarMensagem(
        ApiService.mensagemErro(e, mensagemPadrao: mensagemPadrao),
      );
    } finally {
      _alterandoVinculo = false;
    }

    if (mounted && !_saindo) {
      await carregarVinculoPendente();
    }
  }

  Future<void> _alterarTema(ThemeProvider provider, ThemeMode modo) async {
    if (_alterandoTema || _saindo) return;
    _alterandoTema = true;

    try {
      await provider.alterarTema(modo);
    } catch (e) {
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível salvar a aparência. Tente novamente.',
        ),
      );
    } finally {
      _alterandoTema = false;
    }
  }

  Future<void> _encerrarSessao() async {
    if (_saindo || !mounted) return;
    if (_alterandoVinculo || _alterandoTema) {
      _mostrarMensagem('Aguarde a conclusão da operação para sair.');
      return;
    }
    _saindo = true;

    try {
      await AuthService.logout();
      if (!mounted) return;
      context.go('/selecionar');
    } catch (e) {
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível encerrar a sessão. Tente novamente.',
        ),
      );
    } finally {
      _saindo = false;
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
    if (_saindo) return;
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
                    RadioGroup<ThemeMode>(
                      groupValue: provider.themeMode,
                      onChanged: (ThemeMode? modo) async {
                        if (modo == null) return;
                        await _alterarTema(themeProvider, modo);
                      },
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.system,
                            secondary: Icon(Icons.settings_brightness),
                            title: Text('Sistema'),
                            subtitle: Text('Segue a configuração do celular'),
                          ),
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.light,
                            secondary: Icon(Icons.light_mode),
                            title: Text('Claro'),
                            subtitle: Text('Sempre usar o modo claro'),
                          ),
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.dark,
                            secondary: Icon(Icons.dark_mode),
                            title: Text('Escuro'),
                            subtitle: Text('Sempre usar o modo escuro'),
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
      },
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
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
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
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: tema.colorScheme.onSurfaceVariant,
        ),
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
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
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
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.20)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.error.withValues(alpha: 0.14),
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
          style: TextStyle(
            color: colorScheme.onErrorContainer.withValues(alpha: 0.80),
          ),
        ),
        onTap: _encerrarSessao,
      ),
    );
  }

  Widget tituloSecao(String titulo) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        titulo,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar ao início',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/entregador/inicio'),
        ),
        title: const Text('Configurações do Entregador'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          tituloSecao('Conta'),
          cardVinculoPendente(),
          opcaoMenu(
            icon: Icons.directions_car,
            titulo: 'Veículo e Combustível',
            subtitulo: 'Capacidade, consumo e preço do combustível',
            color: AppColors.primary,
            onTap: () => context.push('/entregador/configuracoes/veiculo'),
          ),
          opcaoMenu(
            icon: Icons.article,
            titulo: 'Relatórios',
            subtitulo: 'Veja seu resumo de entregas',
            color: AppColors.primary,
            onTap: () => context.push('/entregador/relatorios'),
          ),
          const SizedBox(height: 14),
          tituloSecao('Assinatura'),
          opcaoMenu(
            icon: Icons.workspace_premium,
            titulo: 'Meu Plano',
            subtitulo: 'Conhecer planos e limites disponíveis',
            color: AppColors.primary,
            onTap: () => context.push('/entregador/planos'),
          ),
          const SizedBox(height: 14),
          tituloSecao('Preferências'),
          opcaoMenu(
            icon: Icons.notifications,
            titulo: 'Notificações',
            subtitulo: 'Ativar ou desativar alertas',
            color: AppColors.warning,
            onTap: () => context.push('/entregador/notificacoes'),
          ),
          opcaoMenu(
            icon: iconeTema(themeProvider.themeMode),
            titulo: 'Aparência',
            subtitulo: textoTema(themeProvider.themeMode),
            color: Colors.indigo,
            onTap: abrirAparencia,
          ),
          const SizedBox(height: 14),
          tituloSecao('Ajuda'),
          opcaoMenu(
            icon: Icons.support_agent,
            titulo: 'Suporte',
            subtitulo: 'Ajuda e atendimento',
            color: Colors.deepPurple,
            onTap: () => context.push('/entregador/suporte'),
          ),
          opcaoMenu(
            icon: Icons.info,
            titulo: 'Sobre o App',
            subtitulo: 'Informações do Entregue Já',
            color: AppColors.primary,
            onTap: () => context.push('/entregador/sobre'),
          ),
          const SizedBox(height: 8),
          botaoSair(),
        ],
      ),
    );
  }
}
