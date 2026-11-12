import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/empresa_lista_entregas_service.dart';
import '../theme/app_colors.dart';

class EditarEntregaPage extends StatefulWidget {
  final Map<String, dynamic> entrega;

  const EditarEntregaPage({super.key, required this.entrega});

  @override
  State<EditarEntregaPage> createState() => _EditarEntregaPageState();
}

class _EditarEntregaPageState extends State<EditarEntregaPage> {
  late TextEditingController clienteController;
  late TextEditingController enderecoController;
  late TextEditingController valorController;
  late TextEditingController observacaoController;

  @override
  void initState() {
    super.initState();

    clienteController = TextEditingController(
      text: widget.entrega['cliente'] ?? '',
    );

    enderecoController = TextEditingController(
      text: widget.entrega['endereco'] ?? '',
    );

    valorController = TextEditingController(
      text: widget.entrega['valor']?.toString() ?? '',
    );

    observacaoController = TextEditingController(
      text: widget.entrega['observacao'] ?? '',
    );
  }

  Future<void> salvarAlteracoes() async {
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

    if (valor == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Valor inválido')));
      return;
    }

    final sucesso = await EmpresaListaEntregasService.editarEntrega(
      id: widget.entrega['id'],
      cliente: cliente,
      endereco: endereco,
      valor: valor,
      observacao: observacao,
    );

    if (!mounted) return;

    if (sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrega alterada com sucesso')),
      );

      context.pop(true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao editar entrega')));
    }
  }

  @override
  void dispose() {
    clienteController.dispose();
    enderecoController.dispose();
    valorController.dispose();
    observacaoController.dispose();
    super.dispose();
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: maxLines == 1
            ? Icon(icon)
            : Padding(
                padding: const EdgeInsets.only(bottom: 55),
                child: Icon(icon),
              ),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar Entrega'), centerTitle: true),
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
                  icon: Icons.person_outline,
                ),

                const SizedBox(height: 16),

                campo(
                  controller: enderecoController,
                  label: 'Endereço',
                  icon: Icons.location_on_outlined,
                ),

                const SizedBox(height: 16),

                campo(
                  controller: valorController,
                  label: 'Valor',
                  icon: Icons.attach_money,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),

                const SizedBox(height: 16),

                campo(
                  controller: observacaoController,
                  label: 'Observação',
                  icon: Icons.notes,
                  maxLines: 3,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: salvarAlteracoes,
              icon: const Icon(Icons.save),
              label: const Text(
                'Salvar Alterações',
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
