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

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? AppColors.error : AppColors.success,
      ),
    );
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

  // O complemento não integra a localização geográfica: apartamentos e
  // unidades diferentes do mesmo prédio podem compartilhar coordenadas.
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
      // Busca diretamente no backend: se a consulta falhar, não tratamos
      // uma lista antiga/incompleta como se não existissem duplicatas.
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

        // Mantém o fallback original, caso a consulta principal falhe.
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
      controller: controller,
      enabled: !salvando,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted?.call(),
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
      appBar: AppBar(title: const Text('Cadastrar Entrega'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
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
                campo(
                  controller: clienteController,
                  label: 'Cliente',
                  hint: 'Nome do destinatário',
                  icon: Icons.person_outline,
                  textCapitalization: TextCapitalization.words,
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
                ),
                const SizedBox(height: 16),
                campo(
                  controller: numeroController,
                  label: 'Número',
                  hint: 'Ex: 123',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.streetAddress,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: complementoController,
                  label: 'Complemento',
                  hint: 'Apto, bloco, casa...',
                  icon: Icons.home_outlined,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: bairroController,
                  label: 'Bairro',
                  hint: 'Bairro',
                  icon: Icons.location_city_outlined,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: cidadeController,
                  label: 'Cidade',
                  hint: 'Cidade',
                  icon: Icons.location_city,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: ufController,
                  label: 'Estado',
                  hint: 'Ex: PR',
                  icon: Icons.map_outlined,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [LengthLimitingTextInputFormatter(2)],
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
