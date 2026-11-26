import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class RecuperarSenhaEmpresaPage extends StatefulWidget {
  final String emailInicial;

  const RecuperarSenhaEmpresaPage({super.key, this.emailInicial = ''});

  @override
  State<RecuperarSenhaEmpresaPage> createState() =>
      _RecuperarSenhaEmpresaPageState();
}

class _RecuperarSenhaEmpresaPageState extends State<RecuperarSenhaEmpresaPage> {
  late final TextEditingController emailController;
  final codigoController = TextEditingController();
  final emailFocus = FocusNode();
  final codigoFocus = FocusNode();
  final senhaFocus = FocusNode();
  final confirmarSenhaFocus = FocusNode();
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
    emailFocus.dispose();
    codigoFocus.dispose();
    senhaFocus.dispose();
    confirmarSenhaFocus.dispose();
    super.dispose();
  }

  void mostrarMensagem(String mensagem, {bool sucesso = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: sucesso ? Colors.green.shade700 : null,
      ),
    );
  }

  bool emailValido(String email) {
    return email.length <= 254 &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  String mensagemResultado(
    Map<String, dynamic> resultado,
    String mensagemPadrao,
  ) {
    final mensagem = resultado['mensagem'];
    if (mensagem is String && mensagem.trim().isNotEmpty) {
      return mensagem.trim();
    }
    return mensagemPadrao;
  }

  bool codigoInvalidoOuExpirado(String mensagem) {
    final texto = mensagem.toLowerCase();
    return texto.contains('código') &&
        (texto.contains('inválid') || texto.contains('expirad'));
  }

  bool resultadoComSucesso(Map<String, dynamic> resultado) {
    final sucesso = resultado['sucesso'];
    if (sucesso is! bool) {
      throw const FormatException('Resposta inválida');
    }
    return sucesso;
  }

  Future<void> solicitarCodigo() async {
    if (!mounted || carregando || etapa != 0) return;
    final email = emailController.text.trim().toLowerCase();
    if (!emailValido(email)) {
      mostrarMensagem('Informe um e-mail válido.');
      return;
    }
    await enviarCodigo(email, reenvio: false);
  }

  Future<void> reenviarCodigo() async {
    if (!mounted || carregando || etapa != 1) return;
    await enviarCodigo(emailConfirmado, reenvio: true);
  }

  Future<void> enviarCodigo(String email, {required bool reenvio}) async {
    if (!mounted || carregando) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => carregando = true);
    final mensagemPadrao = reenvio
        ? 'Não foi possível reenviar o código. Tente novamente.'
        : 'Não foi possível solicitar o código. Tente novamente.';

    try {
      final resultado = await EmpresaService.solicitarCodigoRecuperacao(email);
      if (!mounted) return;

      if (resultadoComSucesso(resultado)) {
        setState(() {
          emailConfirmado = email;
          codigoConfirmado = '';
          codigoController.clear();
          if (!reenvio) {
            senhaController.clear();
            confirmarSenhaController.clear();
          }
          etapa = 1;
        });
        mostrarMensagem(
          'Se o e-mail estiver cadastrado, um código será enviado. '
          'Confira sua caixa de entrada e o spam.',
          sucesso: true,
        );
      } else {
        mostrarMensagem(mensagemResultado(resultado, mensagemPadrao));
      }
    } catch (e) {
      mostrarMensagem(
        ApiService.mensagemErro(e, mensagemPadrao: mensagemPadrao),
      );
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  Future<void> verificarCodigo() async {
    if (!mounted || carregando || etapa != 1) return;
    final codigo = codigoController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      mostrarMensagem('Digite o código de 6 dígitos recebido por e-mail.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => carregando = true);
    const mensagemPadrao =
        'Não foi possível verificar o código. Tente novamente.';

    try {
      final resultado = await EmpresaService.verificarCodigoRecuperacao(
        emailConfirmado,
        codigo,
      );
      if (!mounted) return;

      if (resultadoComSucesso(resultado)) {
        setState(() {
          codigoConfirmado = codigo;
          etapa = 2;
        });
      } else {
        final mensagem = mensagemResultado(resultado, mensagemPadrao);
        mostrarMensagem(
          codigoInvalidoOuExpirado(mensagem)
              ? 'Código inválido ou expirado. Confira o código ou solicite outro.'
              : mensagem,
        );
      }
    } catch (e) {
      mostrarMensagem(
        ApiService.mensagemErro(e, mensagemPadrao: mensagemPadrao),
      );
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  bool senhaForte(String senha) {
    return senha.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(senha) &&
        RegExp(r'[a-z]').hasMatch(senha) &&
        RegExp(r'[0-9]').hasMatch(senha) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(senha);
  }

  Future<void> redefinirSenha() async {
    if (!mounted || carregando || etapa != 2) return;
    final senha = senhaController.text;
    final confirmacao = confirmarSenhaController.text;
    if (senha.isEmpty || confirmacao.isEmpty) {
      mostrarMensagem('Preencha os dois campos de senha.');
      return;
    }
    if (!senhaForte(senha)) {
      mostrarMensagem(
        'A senha deve ter pelo menos 8 caracteres, com maiúscula, minúscula, número e caractere especial.',
      );
      return;
    }
    if (senha != confirmacao) {
      mostrarMensagem('As senhas não coincidem.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => carregando = true);
    const mensagemPadrao =
        'Não foi possível redefinir a senha. Tente novamente.';

    try {
      final resultado = await EmpresaService.redefinirSenha(
        emailConfirmado,
        codigoConfirmado,
        senha,
      );
      if (!mounted) return;

      if (resultadoComSucesso(resultado)) {
        mostrarMensagem(
          'Senha redefinida com sucesso! Faça login com a nova senha.',
          sucesso: true,
        );
        codigoConfirmado = '';
        codigoController.clear();
        senhaController.clear();
        confirmarSenhaController.clear();
        context.go('/empresa/login');
      } else {
        final mensagem = mensagemResultado(resultado, mensagemPadrao);
        if (codigoInvalidoOuExpirado(mensagem)) {
          setState(() {
            codigoConfirmado = '';
            etapa = 1;
          });
          mostrarMensagem(
            'Código inválido ou expirado. Verifique o código ou solicite outro.',
          );
        } else {
          mostrarMensagem(mensagem);
        }
      }
    } catch (e) {
      mostrarMensagem(
        ApiService.mensagemErro(e, mensagemPadrao: mensagemPadrao),
      );
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  void voltar() {
    if (!mounted || carregando) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (etapa == 0) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/empresa/login');
      }
    } else {
      setState(() {
        codigoConfirmado = '';
        if (etapa == 1) {
          emailConfirmado = '';
          codigoController.clear();
          senhaController.clear();
          confirmarSenhaController.clear();
        }
        etapa--;
      });
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
    FocusNode? focusNode,
    TextInputAction acao = TextInputAction.done,
    VoidCallback? aoEnviar,
  }) {
    final ocultar = senha && !(confirmacao ? mostrarConfirmacao : mostrarSenha);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: !carregando,
      keyboardType: tipo,
      obscureText: ocultar,
      autocorrect: !senha,
      enableSuggestions: !senha,
      inputFormatters: formatadores,
      textInputAction: acao,
      onSubmitted: (_) => aoEnviar?.call(),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
      'Escolha uma nova senha para acessar sua empresa.',
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
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
                          'Recuperação de acesso empresarial',
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
                                  focusNode: senhaFocus,
                                  acao: TextInputAction.next,
                                  aoEnviar: () =>
                                      confirmarSenhaFocus.requestFocus(),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Mínimo de 8 caracteres, com maiúscula, minúscula, número e caractere especial.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                campo(
                                  controller: confirmarSenhaController,
                                  label: 'Confirmar nova senha',
                                  icone: Icons.lock_outline,
                                  senha: true,
                                  confirmacao: true,
                                  focusNode: confirmarSenhaFocus,
                                  acao: TextInputAction.done,
                                  aoEnviar: redefinirSenha,
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
