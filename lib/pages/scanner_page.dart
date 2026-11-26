import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController scannerController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );

  bool codigoLido = false;
  bool avisoCodigoInvalido = false;

  void voltar() {
    if (codigoLido || !mounted) return;
    codigoLido = true;

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/entregador/entregas');
    }
  }

  void mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  void capturarCodigo(BarcodeCapture captura) {
    if (codigoLido || !mounted) return;

    bool encontrouQr = false;

    for (final barcode in captura.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode) continue;
      encontrouQr = true;

      final codigo = barcode.rawValue?.trim();
      if (codigo == null || codigo.isEmpty) continue;

      codigoLido = true;

      if (context.canPop()) {
        context.pop(codigo);
      } else {
        mostrarMensagem('Abra o leitor de QR Code pela tela de entregas.');
        context.go('/entregador/entregas');
      }
      return;
    }

    if (encontrouQr && !avisoCodigoInvalido) {
      avisoCodigoInvalido = true;
      mostrarMensagem('Não foi possível ler o QR Code. Posicione-o novamente.');
    }
  }

  Widget erroCamera(
    BuildContext context,
    MobileScannerException erro, [
    Widget? child,
  ]) {
    final theme = Theme.of(context);
    final String mensagem;

    if (erro.errorCode == MobileScannerErrorCode.permissionDenied) {
      mensagem =
          'Permita o acesso à câmera nas configurações do aplicativo ou do navegador e abra o leitor novamente.';
    } else if (erro.errorCode == MobileScannerErrorCode.unsupported) {
      mensagem =
          'A leitura de QR Code não é compatível com este dispositivo ou navegador.';
    } else {
      mensagem =
          'Não foi possível iniciar ou utilizar a câmera. Verifique se ela está disponível e tente abrir o leitor novamente.';
    }

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Câmera indisponível',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(mensagem, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: voltar,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar às entregas'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    codigoLido = true;
    unawaited(scannerController.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar às entregas',
          icon: const Icon(Icons.arrow_back),
          onPressed: voltar,
        ),
        title: const Text('Escanear QR Code'),
        centerTitle: true,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: scannerController,
            onDetect: capturarCodigo,
            errorBuilder: erroCamera,
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: scannerController,
            builder: (context, estado, child) {
              if (estado.error != null || !estado.isInitialized) {
                return const SizedBox.shrink();
              }
              return child!;
            },
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.black.withValues(alpha: 0.18)),
                  Center(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.primaryLight,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: theme.cardColor.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.qr_code_scanner,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Posicione o QR Code dentro da moldura.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
