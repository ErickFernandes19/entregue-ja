import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class VerificarCadastroPage extends StatefulWidget {
  final String email;

  const VerificarCadastroPage({super.key, required this.email});

  @override
  State<VerificarCadastroPage> createState() => _VerificarCadastroPageState();
}

class _VerificarCadastroPageState extends State<VerificarCadastroPage> {
  final codigoController = TextEditingController();
  bool carregando = false;
  bool reenviando = false;
  int segundosParaReenvio = 0;
  Timer? temporizadorReenvio;

  @override
  void initState() {
    super.initState();
    iniciarEsperaReenvio();
  }

  void iniciarEsperaReenvio() {
    temporizadorReenvio?.cancel();
    setState(() => segundosParaReenvio = 60);
    temporizadorReenvio = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (segundosParaReenvio <= 1) {
        timer.cancel();
        setState(() => segundosParaReenvio = 0);
      } else {
        setState(() => segundosParaReenvio--);
      }
    });
  }

  void mostrarMensagem(String mensagem) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  String mensagemResultado(
    Map<String, dynamic> resultado,
    String mensagemPadrao,
  ) {
    final mensagem = resultado['mensagem']?.toString().trim();
    return mensagem != null && mensagem.isNotEmpty ? mensagem : mensagemPadrao;
  }

  Future<void> reenviarCodigo() async {
    if (!mounted || carregando || reenviando || segundosParaReenvio > 0) {
      return;
    }

    fecharTeclado();
    setState(() => reenviando = true);

    try {
      final resultado = await AuthService.reenviarCodigoCadastro(widget.email);
      if (!mounted) return;

      if (resultado['sucesso'] == true) {
        codigoController.clear();
        iniciarEsperaReenvio();
        mostrarMensagem(
          mensagemResultado(resultado, 'Código reenviado para seu e-mail.'),
        );
      } else {
        mostrarMensagem(
          mensagemResultado(
            resultado,
            'Não foi possível reenviar o código. Tente novamente.',
          ),
        );
      }
    } catch (e) {
      mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível reenviar o código. Tente novamente.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => reenviando = false);
      }
    }
  }

  void fecharTeclado() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void voltarAoCadastro() {
    if (carregando || reenviando) return;
    fecharTeclado();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/entregador/cadastro');
    }
  }

  Future<void> confirmar() async {
    if (!mounted || carregando || reenviando) return;
    fecharTeclado();

    final codigo = codigoController.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      mostrarMensagem('Digite o código de 6 dígitos.');
      return;
    }

    setState(() => carregando = true);

    try {
      final resultado = await AuthService.confirmarCadastroComResultado(
        widget.email,
        codigo,
      );
      if (!mounted) return;

      if (resultado['sucesso'] == true) {
        mostrarMensagem('Cadastro confirmado com sucesso!');
        context.go('/entregador/login');
      } else {
        mostrarMensagem(
          mensagemResultado(
            resultado,
            'Não foi possível confirmar o código. Tente novamente.',
          ),
        );
      }
    } catch (e) {
      mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível confirmar o código. Tente novamente.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  @override
  void dispose() {
    temporizadorReenvio?.cancel();
    codigoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar ao cadastro',
          icon: const Icon(Icons.arrow_back),
          onPressed: carregando || reenviando ? null : voltarAoCadastro,
        ),
        title: const Text('Verificar e-mail'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: fecharTeclado,
        child: Container(
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
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mark_email_read_outlined,
                        size: 72,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Verificar e-mail',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enviamos um código de 6 dígitos para',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
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
                            'Código de verificação',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: codigoController,
                            autofocus: true,
                            enabled: !carregando && !reenviando,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onSubmitted: (_) => confirmar(),
                            onTapOutside: (_) => fecharTeclado(),
                            style: TextStyle(
                              fontSize: 26,
                              letterSpacing: 8,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                            decoration: const InputDecoration(
                              hintText: '000000',
                              prefixIcon: Icon(Icons.pin_outlined),
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'O código é válido por 10 minutos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              onPressed: carregando || reenviando
                                  ? null
                                  : confirmar,
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
                                      'Confirmar cadastro',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed:
                                carregando ||
                                    reenviando ||
                                    segundosParaReenvio > 0
                                ? null
                                : reenviarCodigo,
                            child: Text(
                              reenviando
                                  ? 'Reenviando código...'
                                  : segundosParaReenvio > 0
                                  ? 'Reenviar código em ${segundosParaReenvio}s'
                                  : 'Reenviar código',
                            ),
                          ),
                          TextButton(
                            onPressed: carregando || reenviando
                                ? null
                                : voltarAoCadastro,
                            child: const Text('Voltar ao cadastro'),
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
      ),
    );
  }
}
