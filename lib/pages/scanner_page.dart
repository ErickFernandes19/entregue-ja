import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool codigoLido = false;

  void capturarCodigo(String codigo) {
    if (codigoLido) return;

    setState(() {
      codigoLido = true;
    });

    Navigator.pop(context, codigo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR Code'), centerTitle: true),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (capture.barcodes.isEmpty) return;

              final barcode = capture.barcodes.first;

              if (barcode.rawValue == null) return;

              capturarCodigo(barcode.rawValue!);
            },
          ),

          IgnorePointer(
            child: Container(color: Colors.black.withOpacity(0.18)),
          ),

          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primaryLight, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
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
                  color: theme.cardColor.withOpacity(0.94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.qr_code_scanner, color: AppColors.primary),
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
    );
  }
}
