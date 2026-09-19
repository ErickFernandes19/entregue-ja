import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  final ImagePicker picker = ImagePicker();
  final TextRecognizer textRecognizer = TextRecognizer();

  File? imagem;
  String textoExtraido = '';

  Future<void> tirarFotoELerTexto() async {
    final XFile? foto = await picker.pickImage(source: ImageSource.camera);

    if (foto == null) {
      return;
    }

    final inputImage = InputImage.fromFilePath(foto.path);

    final RecognizedText recognizedText = await textRecognizer.processImage(
      inputImage,
    );

    final textoCompleto = recognizedText.text;
    final textoDestinatario = extrairDestinatario(textoCompleto);

    if (!mounted) return;

    setState(() {
      imagem = File(foto.path);

      textoExtraido = textoDestinatario.trim().isEmpty
          ? textoCompleto
          : textoDestinatario;
    });
  }

  void usarTexto() {
    if (textoExtraido.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum texto foi identificado ainda')),
      );
      return;
    }

    Navigator.pop(context, textoExtraido);
  }

  String extrairDestinatario(String textoCompleto) {
    final linhas = textoCompleto
        .split('\n')
        .map((linha) => linha.trim())
        .where((linha) => linha.isNotEmpty)
        .toList();

    final List<String> resultado = [];
    bool encontrouDestinatario = false;

    for (final texto in linhas) {
      final textoMaiusculo = texto.toUpperCase();

      if (textoMaiusculo.contains('DESTINAT')) {
        encontrouDestinatario = true;
        continue;
      }

      if (encontrouDestinatario) {
        if (textoMaiusculo.contains('REMETENTE') ||
            textoMaiusculo.contains('NOTA') ||
            textoMaiusculo.contains('PESO') ||
            textoMaiusculo.contains('VOLUME') ||
            textoMaiusculo.contains('CHAVE') ||
            textoMaiusculo.contains('NF-E') ||
            textoMaiusculo.contains('DECLARA')) {
          break;
        }

        resultado.add(texto);

        if (resultado.length >= 5) {
          break;
        }
      }
    }

    if (resultado.isNotEmpty) {
      return resultado.join('\n');
    }

    return extrairEnderecoSemDestinatario(linhas);
  }

  String extrairEnderecoSemDestinatario(List<String> linhas) {
    final palavrasEndereco = [
      'RUA',
      'AVENIDA',
      'AV ',
      'AV.',
      'TRAVESSA',
      'TV ',
      'TV.',
      'RODOVIA',
      'ESTRADA',
      'ALAMEDA',
      'PRAÇA',
      'PRACA',
      'CEP',
    ];

    for (int i = 0; i < linhas.length; i++) {
      final linhaMaiuscula = linhas[i].toUpperCase();

      final pareceEndereco = palavrasEndereco.any(
        (palavra) => linhaMaiuscula.contains(palavra),
      );

      if (pareceEndereco) {
        final inicio = i > 0 ? i - 1 : i;
        final fim = (i + 4) < linhas.length ? i + 4 : linhas.length;

        return linhas.sublist(inicio, fim).join('\n');
      }
    }

    return '';
  }

  @override
  void dispose() {
    textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ler etiqueta'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: tirarFotoELerTexto,
              icon: const Icon(Icons.camera_alt),
              label: const Text(
                'Tirar foto da etiqueta',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 18),

          if (imagem != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.file(
                imagem!,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 18),
          ],

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                    theme.brightness == Brightness.dark ? 0.16 : 0.04,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.14),
                      child: const Icon(
                        Icons.document_scanner,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Texto identificado',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  textoExtraido.isEmpty
                      ? 'Nenhum texto lido ainda'
                      : textoExtraido,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: textoExtraido.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: textoExtraido.trim().isEmpty ? null : usarTexto,
              icon: const Icon(Icons.check),
              label: const Text(
                'Usar texto lido',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
