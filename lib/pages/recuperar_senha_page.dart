import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class RecuperarSenhaPage extends StatefulWidget {
  final String emailInicial;

  const RecuperarSenhaPage({super.key, this.emailInicial = ''});

  @override
  State<RecuperarSenhaPage> createState() => _RecuperarSenhaPageState();
}

class _RecuperarSenhaPageState extends State<RecuperarSenhaPage> {
  late final TextEditingController emailController;
  final codigoController = TextEditingController();
  final senhaController = TextEditingController();
  final confirmarSenhaController = TextEditingController();

  int etapa = 0;
  bool carregando = false;
  bool mostrarSenha = false;
  bool mostrarConfirmacao = false;
  String emailConfirmado = '';
  String codigoConfirmado = '';

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController(text: widget.emailInicial);
  }

  @override
  void dispose() {
    emailController.dispose();
    codigoController.dispose();
    senhaController.dispose();
    confirmarSenhaController.dispose();
    super.dispose();
  }

  void mostrarMensagem(String mensagem, {bool sucesso = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: sucesso ? Colors.green.shade700 : null,
      ),
    );
  }

  bool emailValido(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  Future<void> solicitarCodigo() async {
    final email = emailController.text.trim();
    if (!emailValido(email)) {
      mostrarMensagem('Informe um e-mail válido.');
      return;
    }

    setState(() => carregando = true);
    final resultado = await AuthService.solicitarCodigoRecuperacao(email);
    if (!mounted) return;
    setState(() => carregando = false);

    final sucesso = resultado['sucesso'] == true;
    mostrarMensagem(
      resultado['mensagem']?.toString() ?? 'Não foi possível enviar o código.',
      sucesso: sucesso,
    );
    if (sucesso) {
      setState(() {
        emailConfirmado = email;
        codigoController.clear();
        etapa = 1;
      });
    }
  }

  Future<void> reenviarCodigo() async {
    if (carregando) return;
    setState(() => carregando = true);
    final resultado = await AuthService.solicitarCodigoRecuperacao(
      emailConfirmado,
    );
    if (!mounted) return;
    setState(() => carregando = false);
    mostrarMensagem(
      resultado['mensagem']?.toString() ??
          'Não foi possível reenviar o código.',
      sucesso: resultado['sucesso'] == true,
    );
  }

  Future<void> verificarCodigo() async {
    final codigo = codigoController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      mostrarMensagem('Digite o código de 6 dígitos recebido por e-mail.');
      return;
    }

    setState(() => carregando = true);
    final resultado = await AuthService.verificarCodigoRecuperacao(
      emailConfirmado,
      codigo,
    );
    if (!mounted) return;
    setState(() => carregando = false);

    if (resultado['sucesso'] == true) {
      setState(() {
        codigoConfirmado = codigo;
        etapa = 2;
      });
    } else {
      mostrarMensagem(resultado['mensagem']?.toString() ?? 'Código inválido.');
    }
  }

  Future<void> redefinirSenha() async {
    final senha = senhaController.text;
    final confirmacao = confirmarSenhaController.text;
    if (senha.isEmpty || confirmacao.isEmpty) {
      mostrarMensagem('Preencha os dois campos de senha.');
      return;
    }
    if (senha.length < 8) {
      mostrarMensagem('A nova senha deve ter pelo menos 8 caracteres.');
      return;
    }
    if (senha != confirmacao) {
      mostrarMensagem('As senhas não coincidem.');
      return;
    }

    setState(() => carregando = true);
    final resultado = await AuthService.redefinirSenha(
      emailConfirmado,
      codigoConfirmado,
      senha,
    );
    if (!mounted) return;
    setState(() => carregando = false);

    if (resultado['sucesso'] == true) {
      mostrarMensagem(
        'Senha redefinida com sucesso! Faça login com a nova senha.',
        sucesso: true,
      );
      context.pop();
    } else {
      mostrarMensagem(
        resultado['mensagem']?.toString() ??
            'Não foi possível redefinir a senha.',
      );
    }
  }

  void voltar() {
    if (carregando) return;
    if (etapa == 0) {
      context.pop();
    } else {
      setState(() => etapa--);
    }
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required IconData icone,
    TextInputType tipo = TextInputType.text,
    bool senha = false,
    bool confirmacao = false,
    List<TextInputFormatter>? formatadores,
  }) {
    final ocultar = senha && !(confirmacao ? mostrarConfirmacao : mostrarSenha);
    return TextField(
      controller: controller,
      enabled: !carregando,
      keyboardType: tipo,
      obscureText: ocultar,
      inputFormatters: formatadores,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icone),
        suffixIcon: senha
            ? IconButton(
                onPressed: () => setState(() {
                  if (confirmacao) {
                    mostrarConfirmacao = !mostrarConfirmacao;
                  } else {
                    mostrarSenha = !mostrarSenha;
                  }
                }),
                icon: Icon(ocultar ? Icons.visibility : Icons.visibility_off),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titulos = ['Recuperar senha', 'Verificar código', 'Nova senha'];
    final descricoes = [
      'Informe o e-mail cadastrado para receber um código de recuperação.',
      'Digite o código de 6 dígitos enviado para $emailConfirmado.',
      'Escolha uma nova senha para acessar sua conta.',
    ];

    return PopScope(
      canPop: etapa == 0 && !carregando,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) voltar();
      },
      child: Scaffold(
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
                      onPressed: carregando ? null : voltar,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 68, 24, 24),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_reset,
                            size: 72,
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
                          'Recuperação de acesso',
                          style: TextStyle(fontSize: 15, color: Colors.white70),
                        ),
                        const SizedBox(height: 34),
                        Container(
                          width: double.infinity,
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                titulos[etapa],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                descricoes[etapa],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (etapa == 0)
                                campo(
                                  controller: emailController,
                                  label: 'E-mail',
                                  icone: Icons.email_outlined,
                                  tipo: TextInputType.emailAddress,
                                ),
                              if (etapa == 1) ...[
                                campo(
                                  controller: codigoController,
                                  label: 'Código de verificação',
                                  icone: Icons.pin_outlined,
                                  tipo: TextInputType.number,
                                  formatadores: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: carregando
                                        ? null
                                        : reenviarCodigo,
                                    child: const Text('Reenviar código'),
                                  ),
                                ),
                              ],
                              if (etapa == 2) ...[
                                campo(
                                  controller: senhaController,
                                  label: 'Nova senha',
                                  icone: Icons.lock_outline,
                                  senha: true,
                                ),
                                const SizedBox(height: 16),
                                campo(
                                  controller: confirmarSenhaController,
                                  label: 'Confirmar nova senha',
                                  icone: Icons.lock_outline,
                                  senha: true,
                                  confirmacao: true,
                                ),
                              ],
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: carregando
                                      ? null
                                      : (etapa == 0
                                            ? solicitarCodigo
                                            : etapa == 1
                                            ? verificarCodigo
                                            : redefinirSenha),
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
                                      : Text(
                                          etapa == 0
                                              ? 'Enviar código'
                                              : etapa == 1
                                              ? 'Verificar código'
                                              : 'Redefinir senha',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
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
      ),
    );
  }
}
