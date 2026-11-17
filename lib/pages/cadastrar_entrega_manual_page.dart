import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../models/entrega_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cep_service.dart';
import '../services/geocoding_service.dart';
import '../theme/app_colors.dart';

class CadastrarEntregaManualPage extends StatefulWidget {
  const CadastrarEntregaManualPage({super.key});

  @override
  State<CadastrarEntregaManualPage> createState() =>
      _CadastrarEntregaManualPageState();
}

class _CadastrarEntregaManualPageState
    extends State<CadastrarEntregaManualPage> {
  final cepController = TextEditingController();
  final clienteController = TextEditingController();
  final ruaController = TextEditingController();
  final numeroController = TextEditingController();
  final bairroController = TextEditingController();
  final cidadeController = TextEditingController();
  final ufController = TextEditingController();
  final complementoController = TextEditingController();
  final valorController = TextEditingController();
  final observacaoController = TextEditingController();

  bool buscandoCep = false;
  bool salvando = false;
  bool textoInicialOcrProcessado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (textoInicialOcrProcessado) return;
    textoInicialOcrProcessado = true;

    final extra = GoRouterState.of(context).extra;
    String? texto;
    if (extra is Map) {
      final valor = extra['textoOcr'];
      if (valor is String) texto = valor;
    }
    if (texto == null || texto.trim().isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      preencherComTextoOcr(texto!);
    });
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? AppColors.error : AppColors.success,
      ),
    );
  }

  String normalizarLinhaOcr(String valor) {
    const acentos = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const simples = 'AAAAAEEEEIIIIOOOOOUUUUC';
    var texto = valor.toUpperCase();
    for (var i = 0; i < acentos.length; i++) {
      texto = texto.replaceAll(acentos[i], simples[i]);
    }
    return texto.trim();
  }

  String? extrairCampoOcr(List<String> linhas, List<String> rotulos) {
    for (var i = 0; i < linhas.length; i++) {
      final normalizada = normalizarLinhaOcr(linhas[i]);
      for (final rotulo in rotulos) {
        final padrao = RegExp('^${RegExp.escape(rotulo)}\\s*[:\\-]?\\s*');
        final correspondencia = padrao.firstMatch(normalizada);
        if (correspondencia == null) continue;
        final restante = linhas[i].substring(correspondencia.end).trim();
        if (restante.isNotEmpty) return restante;
        if (i + 1 < linhas.length) return linhas[i + 1].trim();
      }
    }
    return null;
  }

  void preencherComTextoOcr(String texto) {
    final linhas = texto
        .split(RegExp(r'\r?\n'))
        .map((linha) => linha.trim())
        .where((linha) => linha.isNotEmpty)
        .toList();
    if (linhas.isEmpty) {
      mostrarMensagem(
        'A etiqueta não contém dados para preencher.',
        erro: true,
      );
      return;
    }

    final cepEncontrado = RegExp(r'\b\d{5}[-\s]?\d{3}\b').firstMatch(texto);
    final cep = cepEncontrado?.group(0)?.replaceAll(RegExp(r'\D'), '');
    final nome = extrairCampoOcr(linhas, ['NOME', 'RECEBEDOR', 'CLIENTE']);
    final bairro = extrairCampoOcr(linhas, ['BAIRRO']);
    final complemento = extrairCampoOcr(linhas, [
      'COMPLEMENTO',
      'COMPL',
      'APTO',
      'APARTAMENTO',
    ]);
    final cidade = extrairCampoOcr(linhas, ['CIDADE', 'MUNICIPIO']);
    final uf = extrairCampoOcr(linhas, ['UF', 'ESTADO']);
    final numero = extrairCampoOcr(linhas, ['NUMERO', 'Nº', 'N°']);
    final ruaRotulada = extrairCampoOcr(linhas, ['LOGRADOURO', 'ENDERECO']);
    final ruaPadrao = RegExp(
      r'^(?:RUA|R\.|AVENIDA|AV\.|AV\s|TRAVESSA|TV\.|ALAMEDA|ESTRADA|RODOVIA|PRACA|PRAÇA)\b',
      caseSensitive: false,
    );
    String? rua = ruaRotulada;
    for (final linha in linhas) {
      if (rua == null && ruaPadrao.hasMatch(normalizarLinhaOcr(linha))) {
        rua = linha;
      }
    }

    String? numeroDaRua = numero;
    if (rua != null) {
      final match = RegExp(r'^(.*?),\s*(\d+[A-Za-z]?)\b').firstMatch(rua);
      if (match != null) {
        rua = match.group(1)!.trim();
        numeroDaRua ??= match.group(2);
      }
    }

    String? cidadeEncontrada = cidade;
    String? ufEncontrada = uf;
    for (final linha in linhas) {
      final match = RegExp(
        r'^(.+?)\s*[-/]\s*([A-Za-z]{2})\s*$',
      ).firstMatch(linha);
      if (match != null && cidadeEncontrada == null) {
        cidadeEncontrada = match.group(1)?.trim();
        ufEncontrada ??= match.group(2)?.toUpperCase();
      }
    }

    final primeira = linhas.first;
    final primeiraNormalizada = normalizarLinhaOcr(primeira);
    final nomeProvavel =
        nome ??
        (primeiraNormalizada.startsWith('DESTINATARIO:')
            ? primeira.substring(primeira.indexOf(':') + 1).trim()
            : (!primeiraNormalizada.startsWith('DESTINATARIO') &&
                      !primeiraNormalizada.startsWith('DEST.') &&
                      !ruaPadrao.hasMatch(primeiraNormalizada) &&
                      !RegExp(r'\d{5}[-\s]?\d{3}').hasMatch(primeira)
                  ? primeira
                  : null));

    setState(() {
      if (nomeProvavel != null && nomeProvavel.isNotEmpty) {
        clienteController.text = nomeProvavel;
      }
      if (cep != null && cep.length == 8) cepController.text = cep;
      if (rua != null && rua.isNotEmpty) ruaController.text = rua;
      if (numeroDaRua != null && numeroDaRua.isNotEmpty) {
        numeroController.text = numeroDaRua;
      }
      if (bairro != null && bairro.isNotEmpty) bairroController.text = bairro;
      if (cidadeEncontrada != null && cidadeEncontrada.isNotEmpty) {
        cidadeController.text = cidadeEncontrada;
      }
      if (ufEncontrada != null && ufEncontrada.trim().length == 2) {
        ufController.text = ufEncontrada.trim().toUpperCase();
      }
      if (complemento != null && complemento.isNotEmpty) {
        complementoController.text = complemento;
      }
    });
    mostrarMensagem('Confira os campos preenchidos antes de cadastrar.');
  }

  Future<void> lerEtiquetaParaCadastro() async {
    if (salvando || buscandoCep) return;
    final texto = await context.push<String>('/entregador/entregas/ocr');
    if (!mounted || texto == null || texto.trim().isEmpty) return;
    preencherComTextoOcr(texto);
  }

  Future<void> buscarCep() async {
    if (buscandoCep || salvando) return;

    final cep = cepController.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (cep.length != 8) {
      mostrarMensagem('Digite um CEP válido com 8 números', erro: true);
      return;
    }

    setState(() => buscandoCep = true);

    try {
      final dados = await CepService.buscarCep(cep);

      if (!mounted) return;

      if (dados == null) {
        mostrarMensagem('CEP não encontrado', erro: true);
        return;
      }

      setState(() {
        ruaController.text = dados['logradouro']?.toString().trim() ?? '';
        bairroController.text = dados['bairro']?.toString().trim() ?? '';
        cidadeController.text = dados['localidade']?.toString().trim() ?? '';
        ufController.text = dados['uf']?.toString().trim() ?? '';
        numeroController.clear();
        complementoController.clear();
      });

      mostrarMensagem('Endereço encontrado. Informe o número.');
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
      mostrarMensagem('Não foi possível consultar o CEP', erro: true);
    } finally {
      if (mounted) setState(() => buscandoCep = false);
    }
  }

  String montarEnderecoCompleto() {
    final cep = cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final rua = ruaController.text.trim();
    final numero = numeroController.text.trim();
    final bairro = bairroController.text.trim();
    final cidade = cidadeController.text.trim();
    final uf = ufController.text.trim().toUpperCase();

    final partes = <String>['$rua, $numero', bairro, '$cidade - $uf'];

    if (cep.length == 8) {
      partes.add('${cep.substring(0, 5)}-${cep.substring(5)}');
    }

    return partes.join(', ');
  }

  String montarEnderecoParaMapa() {
    final cep = cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final rua = ruaController.text.trim();
    final numero = numeroController.text.trim();
    final bairro = bairroController.text.trim();
    final cidade = cidadeController.text.trim();
    final uf = ufController.text.trim().toUpperCase();

    final partes = <String>['$rua, $numero', bairro, cidade, uf];

    if (cep.length == 8) {
      partes.add(cep);
    }

    partes.add('Brasil');

    return partes.join(', ');
  }

  String normalizarEndereco(String endereco) {
    const acentos = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const semAcentos = 'aaaaaeeeeiiiiooooouuuuc';
    var texto = endereco.toLowerCase().trim();

    for (var i = 0; i < acentos.length; i++) {
      texto = texto.replaceAll(acentos[i], semAcentos[i]);
    }

    return texto.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  double? converterValor(String texto) {
    final normalizado = texto.trim().replaceAll(',', '.');
    return double.tryParse(normalizado);
  }

  Future<void> salvarEntrega() async {
    if (salvando || buscandoCep) return;

    final cliente = clienteController.text.trim();
    final cep = cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final rua = ruaController.text.trim();
    final numero = numeroController.text.trim();
    final bairro = bairroController.text.trim();
    final cidade = cidadeController.text.trim();
    final uf = ufController.text.trim().toUpperCase();
    final complemento = complementoController.text.trim();
    final observacao = observacaoController.text.trim();
    final valor = converterValor(valorController.text);

    if (cliente.isEmpty) {
      mostrarMensagem('Informe o nome do cliente', erro: true);
      return;
    }

    if (cep.length != 8) {
      mostrarMensagem('Informe um CEP válido', erro: true);
      return;
    }

    if (rua.isEmpty || numero.isEmpty) {
      mostrarMensagem('Informe a rua e o número da entrega', erro: true);
      return;
    }

    if (bairro.isEmpty || cidade.isEmpty || uf.length != 2) {
      mostrarMensagem('Complete bairro, cidade e estado', erro: true);
      return;
    }

    if (valor == null || !valor.isFinite || valor <= 0) {
      mostrarMensagem('Informe um valor válido para a entrega', erro: true);
      return;
    }

    setState(() => salvando = true);

    try {
      final email = await AuthService.usuarioLogado();
      if (email == null || email.isEmpty) {
        throw StateError('Entregador não autenticado');
      }

      final dados = await ApiService.buscarEntregasDoEntregador(email);
      if (!mounted) return;

      final endereco = montarEnderecoCompleto();
      final enderecoNormalizado = normalizarEndereco(endereco);
      final mesmoEndereco = <EntregaModel>[];
      final duplicadasAtivas = <EntregaModel>[];

      for (final item in dados) {
        final existente = EntregaModel.fromJson(
          Map<String, dynamic>.from(item as Map),
        );
        if (normalizarEndereco(existente.endereco) == enderecoNormalizado) {
          mesmoEndereco.add(existente);
          final status = existente.status.trim().toUpperCase();
          if (!existente.entregue &&
              (status == 'PENDENTE' || status == 'EM_ROTA')) {
            duplicadasAtivas.add(existente);
          }
        }
      }

      if (duplicadasAtivas.isNotEmpty) {
        final quantidade = duplicadasAtivas.length;
        final confirmar = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Endereço já cadastrado'),
            content: Text(
              'Já ${quantidade == 1 ? 'existe 1 entrega' : 'existem $quantidade entregas'} '
              'ativa${quantidade == 1 ? '' : 's'} neste endereço.\n\n'
              '$endereco\n\n'
              'Deseja cadastrar mais uma entrega neste local?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Cadastrar outra'),
              ),
            ],
          ),
        );

        if (!mounted || confirmar != true) return;
      }

      Map<String, double>? coordenadas;

      for (final existente in mesmoEndereco) {
        final lat = existente.latitude;
        final lng = existente.longitude;
        if (lat != null &&
            lng != null &&
            lat.isFinite &&
            lng.isFinite &&
            lat >= -90 &&
            lat <= 90 &&
            lng >= -180 &&
            lng <= 180) {
          coordenadas = {'lat': lat, 'lng': lng};
          debugPrint('Reutilizando coordenadas de entrega no mesmo endereço.');
          break;
        }
      }

      if (coordenadas == null) {
        coordenadas = await GeocodingService.buscarCoordenadas(
          montarEnderecoParaMapa(),
        );

        if (coordenadas == null) {
          coordenadas = await GeocodingService.buscarCoordenadas(
            '$cep, $numero, $cidade - $uf',
          );
        }
      }

      if (!mounted) return;

      final entrega = EntregaModel(
        cliente: cliente,
        endereco: endereco,
        complemento: complemento,
        valor: valor,
        observacao: observacao,
        entregue: false,
        status: 'PENDENTE',
        latitude: coordenadas?['lat'],
        longitude: coordenadas?['lng'],
      );

      context.pop(entrega);
    } catch (e) {
      debugPrint('Erro ao preparar entrega: $e');
      mostrarMensagem(
        'Não foi possível verificar as entregas existentes. Tente novamente.',
        erro: true,
      );
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? suffixText,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
  }) {
    final theme = Theme.of(context);

    return TextField(
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      controller: controller,
      enabled: !salvando,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: (_) {
        if (onSubmitted != null) {
          onSubmitted();
        } else if (textInputAction == TextInputAction.done) {
          FocusScope.of(context).unfocus();
        } else if (textInputAction == TextInputAction.next) {
          FocusScope.of(context).nextFocus();
        }
      },
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffixText,
        suffixIcon: suffixIcon,
        alignLabelWithHint: maxLines > 1,
        prefixIcon: maxLines == 1
            ? Icon(icon)
            : Padding(
                padding: const EdgeInsets.only(bottom: 55),
                child: Icon(icon),
              ),
      ),
    );
  }

  @override
  void dispose() {
    cepController.dispose();
    clienteController.dispose();
    ruaController.dispose();
    numeroController.dispose();
    bairroController.dispose();
    cidadeController.dispose();
    ufController.dispose();
    complementoController.dispose();
    valorController.dispose();
    observacaoController.dispose();
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
          onPressed: salvando
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/entregador/entregas');
                  }
                },
        ),
        title: const Text('Cadastrar Entrega'),
        centerTitle: true,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                    theme.brightness == Brightness.dark ? 0.18 : 0.05,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
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
                        Icons.add_box,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Dados da entrega',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: salvando || buscandoCep
                        ? null
                        : lerEtiquetaParaCadastro,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Ler etiqueta com a câmera'),
                  ),
                ),
                const SizedBox(height: 18),
                campo(
                  controller: clienteController,
                  label: 'Cliente',
                  hint: 'Nome do destinatário',
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: cepController,
                  label: 'CEP',
                  hint: 'Ex: 86800000',
                  icon: Icons.location_searching,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.search,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  suffixIcon: buscandoCep
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'Buscar CEP',
                          onPressed: salvando ? null : buscarCep,
                          icon: const Icon(Icons.search),
                        ),
                  onChanged: (valor) {
                    if (valor.length == 8 && !buscandoCep) {
                      buscarCep();
                    }
                  },
                  onSubmitted: buscarCep,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: ruaController,
                  label: 'Rua',
                  hint: 'Rua ou avenida',
                  icon: Icons.signpost_outlined,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: numeroController,
                  label: 'Número',
                  hint: 'Ex: 123',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: complementoController,
                  label: 'Complemento',
                  hint: 'Apto, bloco, casa...',
                  icon: Icons.home_outlined,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: bairroController,
                  label: 'Bairro',
                  hint: 'Bairro',
                  icon: Icons.location_city_outlined,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: cidadeController,
                  label: 'Cidade',
                  hint: 'Cidade',
                  icon: Icons.location_city,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: ufController,
                  label: 'Estado',
                  hint: 'Ex: PR',
                  icon: Icons.map_outlined,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [LengthLimitingTextInputFormatter(2)],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: valorController,
                  label: 'Valor da entrega',
                  hint: 'Ex: 15,00',
                  icon: Icons.attach_money,
                  suffixText: 'R\$',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: observacaoController,
                  label: 'Observação',
                  hint: 'Ex: Ligar ao chegar, deixar na portaria...',
                  icon: Icons.notes,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: salvando || buscandoCep ? null : salvarEntrega,
              icon: salvando
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(
                salvando ? 'Preparando entrega...' : 'Cadastrar Entrega',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
