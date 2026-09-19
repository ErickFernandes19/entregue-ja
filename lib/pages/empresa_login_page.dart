import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'package:entregue_ja/services/empresa_service.dart' as empresa_service;

import 'empresa_home_page.dart';
import 'empresa_register_page.dart';
import 'selection_page.dart';

class EmpresaLoginPage extends StatefulWidget {
  const EmpresaLoginPage({super.key});

  @override
  State<EmpresaLoginPage> createState() => _EmpresaLoginPageState();
}

class _EmpresaLoginPageState extends State<EmpresaLoginPage> {
  final emailController = TextEditingController();
  final senhaController = TextEditingController();

  bool carregando = false;
  bool mostrarSenha = false;

  Future<void> entrar() async {
    final email = emailController.text.trim();
    final senha = senhaController.text.trim();

    if (email.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preencha e-mail e senha')));
      return;
    }

    setState(() {
      carregando = true;
    });

    final empresa = await empresa_service.EmpresaService.login(email, senha);

    if (!mounted) return;

    setState(() {
      carregando = false;
    });

    if (empresa != null) {
      await empresa_service.EmpresaService.salvarDadosEmpresa(
        email: empresa['email'],
        nome: empresa['nome'],
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EmpresaHomePage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail ou senha inválidos')),
      );
    }
  }

  void voltarParaSelecao() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SelectionPage()),
      (route) => false,
    );
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool senha = false,
  }) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      obscureText: senha && !mostrarSenha,
      keyboardType: senha
          ? TextInputType.visiblePassword
          : TextInputType.emailAddress,
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
  void dispose() {
    emailController.dispose();
    senhaController.dispose();
    super.dispose();
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
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: Colors.white.withOpacity(0.16),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Voltar',
                    onPressed: voltarParaSelecao,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
              ),

              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.business,
                          size: 78,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 18),

                      const Text(
                        'Área da Empresa',
                        style: TextStyle(
                          fontSize: 33,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        'Gerencie entregas e entregadores',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),

                      const SizedBox(height: 34),

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
                            Text(
                              'Bem-vindo',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),

                            const SizedBox(height: 6),

                            Text(
                              'Entre para acessar sua empresa',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),

                            const SizedBox(height: 24),

                            campo(
                              controller: emailController,
                              label: 'E-mail',
                              icon: Icons.email_outlined,
                            ),

                            const SizedBox(height: 16),

                            campo(
                              controller: senhaController,
                              label: 'Senha',
                              icon: Icons.lock_outline,
                              senha: true,
                            ),

                            const SizedBox(height: 24),

                            SizedBox(
                              height: 54,
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: carregando ? null : entrar,
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
                                  'Não possui cadastro?',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const EmpresaRegisterPage(),
                                      ),
                                    );
                                  },
                                  child: const Text('Cadastrar'),
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
            ],
          ),
        ),
      ),
    );
  }
}
