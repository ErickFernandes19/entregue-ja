import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final senhaController = TextEditingController();

  bool carregando = false;
  bool mostrarSenha = false;

  Future<void> entrar() async {
    if (carregando) return;

    final email = emailController.text.trim();
    final senha = senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      mostrarMensagem('Preencha e-mail e senha.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => carregando = true);

    try {
      final usuario = await AuthService.login(email, senha, lancarErro: true);
      if (!mounted) return;

      final emailUsuario = usuario?['email'];
      final nomeUsuario = usuario?['nome'];
      if (emailUsuario is! String ||
          emailUsuario.trim().isEmpty ||
          nomeUsuario is! String) {
        throw const FormatException('Dados do usuário inválidos.');
      }

      await AuthService.salvarUsuario(emailUsuario, nomeUsuario);
      if (!mounted) return;

      context.go('/entregador/inicio');
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível entrar na conta. Tente novamente.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  void mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  void voltarParaSelecao() {
    if (carregando) return;
    context.go('/selecionar');
  }

  @override
  void dispose() {
    emailController.dispose();
    senhaController.dispose();
    super.dispose();
  }

  Widget campoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool senha = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      enabled: !carregando,
      obscureText: senha && !mostrarSenha,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        suffixIcon: senha
            ? IconButton(
                icon: Icon(
                  mostrarSenha ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    mostrarSenha = !mostrarSenha;
                  });
                },
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
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Voltar',
                    onPressed: carregando ? null : voltarParaSelecao,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
              ),

              Positioned.fill(
                top: 56,
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
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.delivery_dining,
                                size: 78,
                                color: Colors.white,
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Text(
                              'Entregue Já',
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),

                            const SizedBox(height: 6),

                            const Text(
                              'Seu parceiro nas entregas',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white70,
                              ),
                            ),

                            const SizedBox(height: 34),

                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.35),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: theme.brightness == Brightness.dark
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
                                  Text(
                                    'Bem-vindo de volta',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  Text(
                                    'Entre para continuar',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  campoTexto(
                                    controller: emailController,
                                    label: 'E-mail',
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                  ),

                                  const SizedBox(height: 16),

                                  campoTexto(
                                    controller: senhaController,
                                    label: 'Senha',
                                    icon: Icons.lock_outline,
                                    senha: true,
                                  ),

                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: carregando
                                          ? null
                                          : () {
                                              context.push(
                                                '/entregador/recuperar-senha',
                                                extra: emailController.text
                                                    .trim(),
                                              );
                                            },
                                      child: const Text('Esqueceu sua senha?'),
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  SizedBox(
                                    height: 54,
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: carregando ? null : entrar,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
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
                                              'Entrar',
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
                                        'Não possui conta?',
                                        style: TextStyle(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: carregando
                                            ? null
                                            : () {
                                                context.push(
                                                  '/entregador/cadastro',
                                                );
                                              },
                                        child: const Text('Criar conta'),
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
            ],
          ),
        ),
      ),
    );
  }
}
