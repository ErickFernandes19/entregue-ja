import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entrega_model.dart';
import '../services/cep_service.dart';
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
  final enderecoController = TextEditingController();
  final valorController = TextEditingController();
  final observacaoController = TextEditingController();

  bool buscandoCep = false;

  Future<void> buscarCep() async {
    if (buscandoCep) return;

    final cep = cepController.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite um CEP válido com 8 números')),
      );
      return;
    }

    setState(() {
      buscandoCep = true;
    });

    final dados = await CepService.buscarCep(cep);

    if (!mounted) return;

    setState(() {
      buscandoCep = false;
    });

    if (dados == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CEP não encontrado')));
      return;
    }

    final logradouro = dados['logradouro']?.toString().trim() ?? '';

    final bairro = dados['bairro']?.toString().trim() ?? '';

    final cidade = dados['localidade']?.toString().trim() ?? '';

    final uf = dados['uf']?.toString().trim() ?? '';

    final partes = <String>[];

    if (logradouro.isNotEmpty) {
      partes.add(logradouro);
    }

    if (bairro.isNotEmpty) {
      partes.add(bairro);
    }

    if (cidade.isNotEmpty && uf.isNotEmpty) {
      partes.add('$cidade - $uf');
    } else if (cidade.isNotEmpty) {
      partes.add(cidade);
    }

    setState(() {
      enderecoController.text = partes.join(', ');
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Endereço encontrado. Complete com o número.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void salvarEntrega() {
    final cliente = clienteController.text.trim();
    final endereco = enderecoController.text.trim();
    final valorTexto = valorController.text.trim().replaceAll(',', '.');

    final observacao = observacaoController.text.trim();

    if (cliente.isEmpty || endereco.isEmpty || valorTexto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha cliente, endereço e valor')),
      );
      return;
    }

    final valor = double.tryParse(valorTexto);

    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Valor inválido')));
      return;
    }

    final entrega = EntregaModel(
      cliente: cliente,
      endereco: endereco,
      valor: valor,
      observacao: observacao,
      entregue: false,
    );

    Navigator.pop(context, entrega);
  }

  @override
  void dispose() {
    cepController.dispose();
    clienteController.dispose();
    enderecoController.dispose();
    valorController.dispose();
    observacaoController.dispose();

    super.dispose();
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    IconData? icon,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
  }) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: (_) {
        onSubmitted?.call();
      },
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        prefixIcon: icon == null
            ? null
            : maxLines == 1
            ? Icon(icon)
            : Padding(
                padding: const EdgeInsets.only(bottom: 55),
                child: Icon(icon),
              ),
        suffixIcon: suffixIcon,
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastrar Entrega Manual'),
        centerTitle: true,
      ),
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
              children: [
                campo(
                  controller: clienteController,
                  label: 'Cliente',
                  hint: 'Nome do destinatário',
                  icon: Icons.person,
                  textCapitalization: TextCapitalization.words,
                ),

                const SizedBox(height: 16),

                campo(
                  controller: cepController,
                  label: 'CEP',
                  hint: 'Ex: 87000-000',
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
                          onPressed: buscarCep,
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
                  controller: enderecoController,
                  label: 'Endereço',
                  hint: 'Rua, número, bairro, cidade - UF',
                  icon: Icons.location_on,
                  textCapitalization: TextCapitalization.words,
                ),

                const SizedBox(height: 6),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Após buscar o CEP, complete com o número e complemento.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                campo(
                  controller: valorController,
                  label: 'Valor',
                  hint: 'Ex: 15,00',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  icon: Icons.attach_money,
                ),

                const SizedBox(height: 16),

                campo(
                  controller: observacaoController,
                  label: 'Observação',
                  hint: 'Ex: Casa azul, deixar na portaria...',
                  maxLines: 3,
                  icon: Icons.notes,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: buscandoCep ? null : salvarEntrega,
              icon: const Icon(Icons.save),
              label: const Text(
                'Salvar Entrega',
                style: TextStyle(fontWeight: FontWeight.bold),
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
