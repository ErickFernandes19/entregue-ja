import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  TextRecognizer? textRecognizer;
  final TextEditingController textoController = TextEditingController();

  Uint8List? imagem;
  bool processando = false;
  bool destinatarioIdentificado = false;

  String normalizar(String valor) {
    const acentos = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const simples = 'AAAAAEEEEIIIIOOOOOUUUUC';
    var resultado = valor.toUpperCase();
    for (var i = 0; i < acentos.length; i++) {
      resultado = resultado.replaceAll(acentos[i], simples[i]);
    }
    return resultado.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool marcadorDestinatario(String linha) {
    final texto = normalizar(linha);
    return RegExp(
      r'^(?:DESTINATARIO|DESTINATARIA|DEST\.?|DADOS DO DESTINATARIO|DADOS DE ENTREGA|ENTREGAR PARA|ENTREGA PARA|RECEBEDOR|CONSIGNATARIO)\s*(?:[:\-–]|$|\s)',
    ).hasMatch(texto);
  }

  bool marcadorOutraSecao(String linha) {
    final texto = normalizar(linha);
    return RegExp(
      r'^(?:REMETENTE|REM\.?|EMITENTE|EXPEDIDOR|ORIGEM|DADOS DO REMETENTE|TRANSPORTADORA|DADOS DA TRANSPORTADORA|NOTA FISCAL|DANFE|NF-?E|CHAVE DE ACESSO|DECLARACAO DE CONTEUDO|CONTEUDO|DESCRICAO DOS PRODUTOS|PRODUTOS|PEDIDO|RASTREAMENTO|CODIGO DE BARRAS|PESO|VOLUME|VALOR TOTAL|FRETE|DOCUMENTO AUXILIAR)\b',
    ).hasMatch(texto);
  }

  bool linhaDeEndereco(String linha) {
    final texto = normalizar(linha);
    return RegExp(
      r'\b(?:RUA|R\.|AVENIDA|AV\.|AV\b|TRAVESSA|TV\.|ALAMEDA|ESTRADA|RODOVIA|PRACA|LOTEAMENTO|CONDOMINIO|VIELA|LARGO|QUADRA|Q\.|RURAL)\b',
    ).hasMatch(texto);
  }

  bool linhaDeCep(String linha) {
    return RegExp(r'\b\d{5}[-\s]?\d{3}\b').hasMatch(linha);
  }

  bool linhaIrrelevante(String linha) {
    final texto = normalizar(linha);
    return marcadorOutraSecao(linha) ||
        RegExp(
          r'^(?:CPF|CNPJ|RG|TELEFONE|TEL\.?|CELULAR|CONTATO|EMAIL|E-MAIL|SKU|COD\.?|CODIGO|REFERENCIA|REF\.?|QTD\.?|QUANTIDADE|DATA|EMISSAO|PAGAMENTO|PIX|TOTAL|PRODUTO|ITEM|ETIQUETA|CEP DE ORIGEM)\b',
        ).hasMatch(texto) ||
        RegExp(r'^\d{11,}$').hasMatch(texto.replaceAll(RegExp(r'\s+'), ''));
  }

  bool linhaComplementar(String linha) {
    final texto = normalizar(linha);
    return linhaDeCep(linha) ||
        RegExp(
          r'^(?:NUMERO|N\.?|Nº|N°|COMPLEMENTO|COMPL\.?|APTO|APARTAMENTO|BLOCO|CASA|BAIRRO|CIDADE|MUNICIPIO|ESTADO|UF|JARDIM|JD\.?|CENTRO|VILA|PARQUE|RESIDENCIAL|DISTRITO)\b',
        ).hasMatch(texto) ||
        RegExp(r'\b[A-Z]{2}\s*[-/]?\s*\d{5}[-\s]?\d{3}\b').hasMatch(texto);
  }

  String? extrairDestinatario(String textoCompleto) {
    final linhas = textoCompleto
        .split(RegExp(r'\r?\n'))
        .map((linha) => linha.trim())
        .where((linha) => linha.isNotEmpty)
        .toList();

    if (linhas.isEmpty) return null;

    final secoes = <List<String>>[];
    for (var i = 0; i < linhas.length; i++) {
      if (!marcadorDestinatario(linhas[i])) continue;
      final secao = <String>[];
      final primeira = linhas[i]
          .replaceFirst(
            RegExp(
              r'^\s*(?:dados\s+(?:do\s+)?destinat[aá]ri[oa]|dados\s+de\s+entrega|destinat[aá]ri[oa]|dest\.?|entregar\s+para|entrega\s+para|recebedor|consignat[aá]rio)\s*[:\-–]?\s*',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      if (primeira.isNotEmpty) secao.add(primeira);
      for (var j = i + 1; j < linhas.length && secao.length < 12; j++) {
        if (marcadorOutraSecao(linhas[j]) || marcadorDestinatario(linhas[j])) {
          break;
        }
        secao.add(linhas[j]);
      }
      secoes.add(secao);
    }

    if (secoes.isEmpty) secoes.add(linhas);

    for (final secao in secoes) {
      final enderecoIndex = secao.indexWhere(
        (linha) => linhaDeEndereco(linha) && !linhaIrrelevante(linha),
      );
      if (enderecoIndex < 0) continue;

      final resultado = <String>[];
      if (enderecoIndex > 0) {
        final anterior = secao[enderecoIndex - 1];
        if (!linhaIrrelevante(anterior) &&
            !linhaDeEndereco(anterior) &&
            !linhaDeCep(anterior) &&
            anterior.length >= 3 &&
            !RegExp(r'^\d+$').hasMatch(anterior)) {
          resultado.add(anterior);
        }
      }
      resultado.add(secao[enderecoIndex]);
      for (
        var i = enderecoIndex + 1;
        i < secao.length && resultado.length < 7;
        i++
      ) {
        final linha = secao[i];
        if (linhaIrrelevante(linha) || linhaDeEndereco(linha)) break;
        if (linhaComplementar(linha) ||
            RegExp(r'^\d{1,6}\s*(?:[,\-/]|$)').hasMatch(linha) ||
            (resultado.length > 1 &&
                RegExp(
                  r'^[\p{L}\s]+\s*[-/]\s*[A-Za-z]{2}$',
                  unicode: true,
                ).hasMatch(linha))) {
          resultado.add(linha);
        } else {
          break;
        }
      }
      return resultado.join('\n');
    }
    return null;
  }

  Future<void> tirarFotoELerTexto() async {
    if (processando) return;

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A leitura automática de etiquetas está disponível apenas no aplicativo Android ou iOS. Preencha os dados manualmente nesta versão.',
          ),
        ),
      );
      return;
    }

    setState(() => processando = true);

    try {
      final foto = await picker.pickImage(source: ImageSource.camera);
      if (foto == null) return;

      final bytes = await foto.readAsBytes();
      textRecognizer ??= TextRecognizer();
      final recognizedText = await textRecognizer!.processImage(
        InputImage.fromFilePath(foto.path),
      );
      final destinatario = extrairDestinatario(recognizedText.text);

      if (!mounted) return;

      setState(() {
        imagem = bytes;
        destinatarioIdentificado = destinatario != null;
        textoController.text = destinatario ?? '';
      });

      if (destinatario == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível identificar o destinatário. Tire outra foto ou preencha os dados manualmente.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível ler a etiqueta: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => processando = false);
    }
  }

  void usarTexto() {
    final texto = textoController.text.trim();
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe os dados do destinatário.')),
      );
      return;
    }
    context.pop(texto);
  }

  @override
  void dispose() {
    textoController.dispose();
    textRecognizer?.close();
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
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/entregador/entregas');
            }
          },
        ),
        title: const Text('Ler etiqueta'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: processando ? null : tirarFotoELerTexto,
              icon: processando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(
                processando ? 'Lendo etiqueta...' : 'Tirar foto da etiqueta',
                style: const TextStyle(fontWeight: FontWeight.bold),
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
              child: Image.memory(
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
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.16 : 0.04,
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
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.14,
                      ),
                      child: const Icon(
                        Icons.document_scanner,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Dados do destinatário',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  destinatarioIdentificado
                      ? 'Confira os dados reconhecidos e corrija se necessário.'
                      : 'O texto deve conter somente os dados do destinatário. Você pode corrigir ou preencher manualmente.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: textoController,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Nome, rua, número, complemento, bairro, cidade, UF e CEP',
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
              onPressed: processando ? null : usarTexto,
              icon: const Icon(Icons.check),
              label: const Text(
                'Usar dados do destinatário',
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
