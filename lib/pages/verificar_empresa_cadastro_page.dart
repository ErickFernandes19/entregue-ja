import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class VerificarEmpresaCadastroPage extends StatefulWidget {
  final String email;

  const VerificarEmpresaCadastroPage({super.key, required this.email});

  @override
  State<VerificarEmpresaCadastroPage> createState() =>
      _VerificarEmpresaCadastroPageState();
}

class _VerificarEmpresaCadastroPageState
    extends State<VerificarEmpresaCadastroPage> {
  final codigoController = TextEditingController();
  bool carregando = false;
  bool reenviando = false;
  int segundosParaReenvio = 0;
  Timer? temporizadorReenvio;

  void voltarAoCadastro() {
    if (carregando || reenviando) return;

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/empresa/cadastro');
    }
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
    final mensagem = resultado['mensagem'];
    if (mensagem is String && mensagem.trim().isNotEmpty) {
      return mensagem.trim();
    }
    return mensagemPadrao;
  }

  void iniciarContagemReenvio() {
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

  Future<void> reenviarCodigo() async {
    if (!mounted || carregando || reenviando || segundosParaReenvio > 0) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => reenviando = true);

    try {
      final resultado = await EmpresaService.reenviarCodigoCadastro(
        widget.email,
      );
      if (!mounted) return;

      if (resultado['sucesso'] is! bool) {
        throw const FormatException('Resultado inválido');
      }

      final sucesso = resultado['sucesso'] == true;
      final mensagem = mensagemResultado(
        resultado,
        sucesso
            ? 'Novo código enviado para seu e-mail.'
            : 'Não foi possível reenviar o código. Tente novamente.',
      );

      if (sucesso) {
        codigoController.clear();
        iniciarContagemReenvio();
      }

      mostrarMensagem(mensagem);
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

  Future<void> confirmar() async {
    if (!mounted || carregando || reenviando) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final codigo = codigoController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(codigo)) {
      mostrarMensagem('Digite o código de 6 dígitos.');
      return;
    }

    setState(() => carregando = true);

    try {
      final resultado = await EmpresaService.confirmarCadastroComResultado(
        widget.email,
        codigo,
      );
      if (!mounted) return;

      if (resultado['sucesso'] is! bool) {
        throw const FormatException('Resultado inválido');
      }

      final sucesso = resultado['sucesso'] == true;
      mostrarMensagem(
        mensagemResultado(
          resultado,
          sucesso
              ? 'Cadastro da empresa confirmado com sucesso!'
              : 'Não foi possível confirmar o código. Tente novamente.',
        ),
      );

      if (sucesso) {
        context.go('/empresa/login');
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
                  padding: const EdgeInsets.fromLTRB(24, 68, 24, 24),
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
                            TextButton.icon(
                              onPressed:
                                  carregando ||
                                      reenviando ||
                                      segundosParaReenvio > 0
                                  ? null
                                  : reenviarCodigo,
                              icon: reenviando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                              label: Text(
                                reenviando
                                    ? 'Reenviando código...'
                                    : segundosParaReenvio > 0
                                    ? 'Reenviar código em ${segundosParaReenvio}s'
                                    : 'Reenviar código',
                              ),
                            ),
                            const SizedBox(height: 4),
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
              Positioned(
                top: 8,
                left: 8,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Voltar ao cadastro',
                    onPressed: carregando || reenviando
                        ? null
                        : voltarAoCadastro,
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
