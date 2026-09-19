import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'login_page.dart';

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

  Future<void> cadastrar() async {
    final nome = nomeController.text.trim();
    final email = emailController.text.trim();
    final senha = senhaController.text.trim();
    final confirmarSenha = confirmarSenhaController.text.trim();

    if (nome.isEmpty ||
        email.isEmpty ||
        senha.isEmpty ||
        confirmarSenha.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preencha todos os campos')));
      return;
    }

    if (senha != confirmarSenha) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('As senhas não conferem')));
      return;
    }

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
        const SnackBar(content: Text('Cadastro realizado com sucesso')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao cadastrar usuário')),
      );
    }
  }

  @override
  void dispose() {
    nomeController.dispose();
    emailController.dispose();
    senhaController.dispose();
    confirmarSenhaController.dispose();
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
  }) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
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
                            theme.brightness == Brightness.dark ? 0.28 : 0.12,
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
                        ),

                        const SizedBox(height: 16),

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
                          mostrar: mostrarSenha,
                          onMostrar: () {
                            setState(() {
                              mostrarSenha = !mostrarSenha;
                            });
                          },
                        ),

                        const SizedBox(height: 16),

                        campoTexto(
                          controller: confirmarSenhaController,
                          label: 'Confirmar senha',
                          icon: Icons.lock_reset,
                          senha: true,
                          mostrar: mostrarConfirmarSenha,
                          onMostrar: () {
                            setState(() {
                              mostrarConfirmarSenha = !mostrarConfirmarSenha;
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
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginPage(),
                                  ),
                                );
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
        ),
      ),
    );
  }
}
