import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nomeController = TextEditingController();
  final emailController = TextEditingController();
  final senhaController = TextEditingController();
  final confirmarSenhaController = TextEditingController();

  bool carregando = false;
  bool mostrarSenha = false;
  bool mostrarConfirmarSenha = false;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('As senhas não conferem')));
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      carregando = true;
    });

    final sucesso = await AuthService.cadastrar(nome, email, senha);

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

      context.push('/entregador/verificar-cadastro', extra: email);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível enviar o código de verificação'),
        ),
      );
    }
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

  Widget campoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool senha = false,
    bool mostrar = false,
    VoidCallback? onMostrar,
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
      enableSuggestions: !senha,
      obscureText: senha && !mostrar,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        suffixIcon: senha
            ? IconButton(
                icon: Icon(mostrar ? Icons.visibility_off : Icons.visibility),
                onPressed: onMostrar,
              )
            : null,
        labelText: label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar ao login',
          icon: const Icon(Icons.arrow_back),
          onPressed: carregando
              ? null
              : () {
                  context.go('/entregador/login');
                },
        ),
        title: const Text('Criar Conta'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 48).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1,
                          size: 72,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Criar Conta',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Cadastre-se para começar suas entregas',
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
                            campoTexto(
                              controller: nomeController,
                              label: 'Nome',
                              icon: Icons.person_outline,
                              onSubmitted: () => emailFocus.requestFocus(),
                            ),

                            const SizedBox(height: 16),

                            campoTexto(
                              controller: emailController,
                              label: 'E-mail',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              focusNode: emailFocus,
                              onSubmitted: () => senhaFocus.requestFocus(),
                            ),

                            const SizedBox(height: 16),

                            campoTexto(
                              controller: senhaController,
                              label: 'Senha',
                              icon: Icons.lock_outline,
                              senha: true,
                              mostrar: mostrarSenha,
                              focusNode: senhaFocus,
                              onSubmitted: () =>
                                  confirmarSenhaFocus.requestFocus(),
                              onMostrar: () {
                                setState(() {
                                  mostrarSenha = !mostrarSenha;
                                });
                              },
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

                            campoTexto(
                              controller: confirmarSenhaController,
                              label: 'Confirmar senha',
                              icon: Icons.lock_reset,
                              senha: true,
                              mostrar: mostrarConfirmarSenha,
                              focusNode: confirmarSenhaFocus,
                              textInputAction: TextInputAction.done,
                              onSubmitted: cadastrar,
                              onMostrar: () {
                                setState(() {
                                  mostrarConfirmarSenha =
                                      !mostrarConfirmarSenha;
                                });
                              },
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
                                        'Cadastrar',
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
                                    context.go('/entregador/login');
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
              );
            },
          ),
        ),
      ),
    );
  }
}
