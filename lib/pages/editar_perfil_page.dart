import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class EditarPerfilPage extends StatefulWidget {
  final String nome;
  final String email;

  const EditarPerfilPage({super.key, required this.nome, required this.email});

  @override
  State<EditarPerfilPage> createState() => _EditarPerfilPageState();
}

class _EditarPerfilPageState extends State<EditarPerfilPage> {
  late TextEditingController nomeController;
  late TextEditingController emailController;
  final FocusNode nomeFocus = FocusNode();
  final FocusNode emailFocus = FocusNode();

  bool salvando = false;

  @override
  void initState() {
    super.initState();
    nomeController = TextEditingController(text: widget.nome);
    emailController = TextEditingController(text: widget.email);
  }

  void mostrarMensagem(String mensagem, {bool sucesso = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: sucesso ? AppColors.success : null,
        ),
      );
  }

  Future<void> salvar() async {
    if (salvando) return;

    FocusScope.of(context).unfocus();

    final nome = nomeController.text.trim();
    final email = emailController.text.trim().toLowerCase();

    if (nome.isEmpty) {
      mostrarMensagem('Informe seu nome.');
      nomeFocus.requestFocus();
      return;
    }

    if (email.isEmpty) {
      mostrarMensagem('Informe seu e-mail.');
      emailFocus.requestFocus();
      return;
    }

    if (email.length > 254 ||
        !RegExp(
          r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+$',
        ).hasMatch(email)) {
      mostrarMensagem('Informe um e-mail válido.');
      emailFocus.requestFocus();
      return;
    }

    setState(() => salvando = true);

    try {
      final resultado = await AuthService.atualizarPerfil(
        nome: nome,
        email: email,
        lancarErro: true,
      );

      if (!mounted) return;

      if (resultado == null) {
        throw const ApiException(
          'Não foi possível confirmar a atualização do perfil. Confira seus dados antes de tentar novamente.',
        );
      }

      mostrarMensagem('Perfil atualizado com sucesso!', sucesso: true);
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/entregador/perfil');
      }
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível atualizar o perfil. Tente novamente.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => salvando = false);
      }
    }
  }

  @override
  void dispose() {
    nomeController.dispose();
    emailController.dispose();
    nomeFocus.dispose();
    emailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar ao perfil',
          icon: const Icon(Icons.arrow_back),
          onPressed: salvando
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop(false);
                  } else {
                    context.go('/entregador/perfil');
                  }
                },
        ),
        title: const Text('Editar Perfil'),
        centerTitle: true,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.20 : 0.05,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.12,
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Informações pessoais',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: nomeController,
                    focusNode: nomeFocus,
                    enabled: !salvando,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => emailFocus.requestFocus(),
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: emailController,
                    focusNode: emailFocus,
                    enabled: !salvando,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    autocorrect: false,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: salvando ? null : salvar,
                icon: salvando
                    ? const SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  salvando ? 'Salvando...' : 'Salvar',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
