import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import 'package:entregue_ja/services/empresa_service.dart' as empresa_service;

class EmpresaRegisterPage extends StatefulWidget {
  const EmpresaRegisterPage({super.key});

  @override
  State<EmpresaRegisterPage> createState() => _EmpresaRegisterPageState();
}

class _EmpresaRegisterPageState extends State<EmpresaRegisterPage> {
  final nomeController = TextEditingController();
  final emailController = TextEditingController();
  final senhaController = TextEditingController();
  final confirmarSenhaController = TextEditingController();

  bool carregando = false;
  bool mostrarSenha = false;
  bool mostrarConfirmacao = false;

  final emailFocus = FocusNode();
  final senhaFocus = FocusNode();
  final confirmarSenhaFocus = FocusNode();

  bool senhaForte(String senha) {
    return senha.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(senha) &&
        RegExp(r'[a-z]').hasMatch(senha) &&
        RegExp(r'[0-9]').hasMatch(senha) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(senha);
  }

  void mostrarErro(String mensagem) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> cadastrar() async {
    final nome = nomeController.text.trim();
    final email = emailController.text.trim();
    final senha = senhaController.text;
    final confirmarSenha = confirmarSenhaController.text;

    if (nome.isEmpty ||
        email.isEmpty ||
        senha.isEmpty ||
        confirmarSenha.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preencha todos os campos')));
      return;
    }

    if (!senhaForte(senha)) {
      mostrarErro(
        'A senha deve ter pelo menos 8 caracteres, incluindo letra maiúscula, '
        'minúscula, número e caractere especial.',
      );
      return;
    }

    if (senha != confirmarSenha) {
      mostrarErro('As senhas não coincidem.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      carregando = true;
    });

    final sucesso = await empresa_service.EmpresaService.cadastrar(
      nome,
      email,
      senha,
    );

    if (!mounted) return;

    setState(() {
      carregando = false;
    });

    if (sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Código de verificação enviado para seu e-mail'),
        ),
      );

      context.push('/empresa/verificar-cadastro', extra: email);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao solicitar cadastro da empresa')),
      );
    }
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool senha = false,
    bool confirmacao = false,
    TextInputType keyboardType = TextInputType.text,
    FocusNode? focusNode,
    TextInputAction textInputAction = TextInputAction.next,
    VoidCallback? onSubmitted,
  }) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onSubmitted: (_) => onSubmitted?.call(),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      enabled: !carregando,
      autocorrect: false,
      obscureText: senha && !(confirmacao ? mostrarConfirmacao : mostrarSenha),
      enableSuggestions: !senha,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        suffixIcon: senha
            ? IconButton(
                icon: Icon(
                  (confirmacao ? mostrarConfirmacao : mostrarSenha)
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    if (confirmacao) {
                      mostrarConfirmacao = !mostrarConfirmacao;
                    } else {
                      mostrarSenha = !mostrarSenha;
                    }
                  });
                },
              )
            : null,
        labelText: label,
      ),
    );
  }

  @override
  void dispose() {
    nomeController.dispose();
    emailController.dispose();
    senhaController.dispose();
    confirmarSenhaController.dispose();
    emailFocus.dispose();
    senhaFocus.dispose();
    confirmarSenhaFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 68, 24, 24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_business,
                          size: 72,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Cadastrar Empresa',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Crie uma conta para gerenciar suas entregas',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: Colors.white70),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withOpacity(
                              0.35,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(
                                theme.brightness == Brightness.dark
                                    ? 0.28
                                    : 0.12,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            campo(
                              controller: nomeController,
                              label: 'Nome da empresa',
                              icon: Icons.business_outlined,
                              onSubmitted: () => emailFocus.requestFocus(),
                            ),
                            const SizedBox(height: 16),
                            campo(
                              controller: emailController,
                              label: 'E-mail',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              focusNode: emailFocus,
                              onSubmitted: () => senhaFocus.requestFocus(),
                            ),
                            const SizedBox(height: 16),
                            campo(
                              controller: senhaController,
                              label: 'Senha',
                              icon: Icons.lock_outline,
                              senha: true,
                              focusNode: senhaFocus,
                              onSubmitted: () =>
                                  confirmarSenhaFocus.requestFocus(),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Mínimo de 8 caracteres, com maiúscula, minúscula, número e símbolo.',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            campo(
                              controller: confirmarSenhaController,
                              label: 'Confirmar senha',
                              icon: Icons.lock_outline,
                              senha: true,
                              confirmacao: true,
                              focusNode: confirmarSenhaFocus,
                              textInputAction: TextInputAction.done,
                              onSubmitted: cadastrar,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 54,
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: carregando ? null : cadastrar,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: carregando
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Cadastrar Empresa',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Já possui conta?',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    context.go('/empresa/login');
                                  },
                                  child: const Text('Entrar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: Colors.white.withOpacity(0.16),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Voltar ao login',
                    onPressed: carregando
                        ? null
                        : () {
                            context.go('/empresa/login');
                          },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
