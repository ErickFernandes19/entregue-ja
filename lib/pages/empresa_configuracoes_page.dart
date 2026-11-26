import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class EmpresaConfiguracoesPage extends StatefulWidget {
  const EmpresaConfiguracoesPage({super.key});

  @override
  State<EmpresaConfiguracoesPage> createState() =>
      _EmpresaConfiguracoesPageState();
}

class _EmpresaConfiguracoesPageState extends State<EmpresaConfiguracoesPage> {
  bool _saindo = false;
  bool _abrindoTela = false;
  bool _abrindoAparencia = false;
  bool _alterandoTema = false;

  void _mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _abrirTela(String rota) async {
    if (!mounted ||
        _saindo ||
        _abrindoTela ||
        _abrindoAparencia ||
        _alterandoTema) {
      return;
    }

    _abrindoTela = true;
    try {
      await context.push(rota);
    } catch (e) {
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível abrir esta tela. Tente novamente.',
        ),
      );
    } finally {
      _abrindoTela = false;
    }
  }

  void _voltarAoInicio() {
    if (!mounted ||
        _saindo ||
        _abrindoTela ||
        _abrindoAparencia ||
        _alterandoTema) {
      return;
    }
    try {
      context.go('/empresa/inicio');
    } catch (e) {
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível retornar ao início. Tente novamente.',
        ),
      );
    }
  }

  Future<void> _alterarTema(ThemeProvider provider, ThemeMode modo) async {
    if (!mounted || _saindo || _alterandoTema) return;
    if (provider.themeMode == modo) return;
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
    if (!mounted || _saindo || _abrindoTela || _abrindoAparencia) return;
    if (_alterandoTema) {
      _mostrarMensagem(
        'Aguarde a conclusão da alteração de aparência para sair.',
      );
      return;
    }

    setState(() => _saindo = true);
    try {
      await EmpresaService.logoutEmpresa();
      final token = await EmpresaService.obterTokenEmpresa();
      if (token != null && token.isNotEmpty) {
        throw const ApiException(
          'Não foi possível confirmar o encerramento da sessão. Tente novamente.',
        );
      }
      if (!mounted) return;
      context.go('/selecionar');
    } catch (e) {
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível concluir o encerramento da sessão. Tente novamente.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saindo = false);
      }
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
    if (!mounted ||
        _saindo ||
        _abrindoTela ||
        _abrindoAparencia ||
        _alterandoTema) {
      return;
    }
    _abrindoAparencia = true;
    try {
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
                      RadioGroup<ThemeMode>(
                        groupValue: provider.themeMode,
                        onChanged: (modo) async {
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
    } catch (e) {
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível abrir as opções de aparência.',
        ),
      );
    } finally {
      _abrindoAparencia = false;
    }
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
        onTap: _saindo ? null : onTap,
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
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.20),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.error.withValues(alpha: 0.14),
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
            color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.80),
          ),
        ),
        onTap: _saindo ? null : _encerrarSessao,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    final theme = Theme.of(context);

    return PopScope(
      canPop: !_saindo,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Voltar ao início',
            icon: const Icon(Icons.arrow_back),
            onPressed: _saindo ? null : _voltarAoInicio,
          ),
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
              icon: Icons.groups,
              titulo: 'Meus Entregadores',
              subtitulo: 'Ver entregadores vinculados',
              color: AppColors.success,
              onTap: () => _abrirTela('/empresa/entregadores'),
            ),

            opcao(
              context: context,
              icon: Icons.person_add,
              titulo: 'Vincular Entregador',
              subtitulo: 'Enviar solicitação de vínculo',
              color: Colors.orange,
              onTap: () => _abrirTela('/empresa/vincular-entregador'),
            ),

            const SizedBox(height: 14),

            Text(
              'Assinatura',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 12),

            opcao(
              context: context,
              icon: Icons.workspace_premium,
              titulo: 'Meu Plano',
              subtitulo: 'Conhecer planos e limites disponíveis',
              color: AppColors.primary,
              onTap: () => _abrirTela('/empresa/planos'),
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
              onTap: () => _abrirTela('/empresa/notificacoes'),
            ),

            opcao(
              context: context,
              icon: iconeTema(themeProvider.themeMode),
              titulo: 'Aparência',
              subtitulo: textoTema(themeProvider.themeMode),
              color: Colors.indigo,
              onTap: abrirAparencia,
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
              onTap: () => _abrirTela('/empresa/suporte'),
            ),

            opcao(
              context: context,
              icon: Icons.info,
              titulo: 'Sobre o App',
              subtitulo: 'Informações do Entregue Já',
              color: AppColors.primary,
              onTap: () => _abrirTela('/empresa/sobre'),
            ),

            botaoSair(context),
          ],
        ),
      ),
    );
  }
}
