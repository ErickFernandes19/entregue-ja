import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
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
  bool carregando = false;

  @override
  void initState() {
    super.initState();
    clienteController = TextEditingController(
      text: widget.entrega['cliente']?.toString() ?? '',
    );
    enderecoController = TextEditingController(
      text: widget.entrega['endereco']?.toString() ?? '',
    );
    valorController = TextEditingController(
      text: widget.entrega['valor']?.toString() ?? '',
    );
    observacaoController = TextEditingController(
      text: widget.entrega['observacao']?.toString() ?? '',
    );
  }

  void mostrarMensagem(String mensagem) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> salvarAlteracoes() async {
    if (!mounted || carregando) return;
    FocusScope.of(context).unfocus();
    final cliente = clienteController.text.trim();
    final endereco = enderecoController.text.trim();
    final valorTexto = valorController.text.trim().replaceAll(',', '.');
    final observacao = observacaoController.text.trim();

    if (cliente.isEmpty) {
      mostrarMensagem('Informe o nome do cliente.');
      return;
    }
    if (endereco.isEmpty) {
      mostrarMensagem('Informe o endereço da entrega.');
      return;
    }
    if (valorTexto.isEmpty) {
      mostrarMensagem('Informe o valor da entrega.');
      return;
    }

    final valor = double.tryParse(valorTexto);
    if (valor == null || !valor.isFinite || valor <= 0) {
      mostrarMensagem('Informe um valor válido maior que zero.');
      return;
    }

    final id = int.tryParse(widget.entrega['id']?.toString() ?? '');
    if (id == null || id <= 0) {
      mostrarMensagem(
        'Não foi possível identificar a entrega. Atualize a lista e tente novamente.',
      );
      return;
    }

    setState(() => carregando = true);
    bool sucesso = false;
    try {
      sucesso = await EmpresaListaEntregasService.editarEntrega(
        id: id,
        cliente: cliente,
        endereco: endereco,
        valor: valor,
        observacao: observacao,
        lancarErro: true,
      );
      if (!sucesso) {
        throw const ApiException(
          'Não foi possível confirmar a alteração. Consulte os detalhes da entrega antes de tentar novamente.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível editar a entrega. Consulte os detalhes antes de tentar novamente.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }

    if (!mounted || !sucesso) return;
    mostrarMensagem('Entrega alterada com sucesso');
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go('/empresa/entregas');
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
    TextInputAction? textInputAction,
    int maxLines = 1,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      enabled: !carregando,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      scrollPadding: const EdgeInsets.only(bottom: 120),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar aos detalhes da entrega',
          icon: const Icon(Icons.arrow_back),
          onPressed: carregando
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop(false);
                  } else {
                    context.go('/empresa/entregas');
                  }
                },
        ),
        title: const Text('Editar Entrega'),
        centerTitle: true,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.18 : 0.05,
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
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: enderecoController,
                  label: 'Endereço',
                  icon: Icons.location_on_outlined,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                campo(
                  controller: valorController,
                  label: 'Valor',
                  icon: Icons.attach_money,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
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
              onPressed: carregando ? null : salvarAlteracoes,
              icon: carregando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
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
