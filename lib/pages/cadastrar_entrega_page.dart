import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cep_service.dart';
import '../services/empresa_entrega_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class CadastrarEntregaPage extends StatefulWidget {
  const CadastrarEntregaPage({super.key});

  @override
  State<CadastrarEntregaPage> createState() => _CadastrarEntregaPageState();
}

class _CadastrarEntregaPageState extends State<CadastrarEntregaPage> {
  final cepController = TextEditingController();
  final clienteController = TextEditingController();
  final enderecoController = TextEditingController();
  final valorController = TextEditingController();
  final observacaoController = TextEditingController();

  List<dynamic> entregadores = [];

  String? entregadorSelecionado;

  bool carregando = false;
  bool carregandoEntregadores = true;
  bool buscandoCep = false;

  @override
  void initState() {
    super.initState();
    carregarEntregadores();
  }

  Future<void> carregarEntregadores() async {
    final lista = await EmpresaService.buscarEntregadores();

    if (!mounted) return;

    setState(() {
      entregadores = lista;
      carregandoEntregadores = false;

      if (lista.isNotEmpty) {
        entregadorSelecionado = lista.first['email']?.toString();
      }
    });
  }

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

  double? converterValor(String texto) {
    return double.tryParse(texto.trim().replaceAll(',', '.'));
  }

  Future<void> cadastrarEntrega() async {
    if (carregando) return;

    final cliente = clienteController.text.trim();
    final endereco = enderecoController.text.trim();
    final observacao = observacaoController.text.trim();

    final valor = converterValor(valorController.text);

    if (cliente.isEmpty || endereco.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha cliente e endereço')),
      );

      return;
    }

    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido para a entrega')),
      );

      return;
    }

    if (entregadorSelecionado == null || entregadorSelecionado!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecione um entregador')));

      return;
    }

    final empresaEmail = await EmpresaService.empresaLogada();

    if (!mounted) return;

    if (empresaEmail == null || empresaEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível identificar a empresa logada'),
        ),
      );

      return;
    }

    setState(() {
      carregando = true;
    });

    final resultado = await EmpresaEntregaService.cadastrarEntrega(
      empresaEmail: empresaEmail,
      entregadorEmail: entregadorSelecionado!,
      cliente: cliente,
      endereco: endereco,
      valor: valor,
      observacao: observacao,
    );

    if (!mounted) return;

    setState(() {
      carregando = false;
    });

    if (resultado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível cadastrar a entrega')),
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Entrega cadastrada com sucesso'),
        backgroundColor: AppColors.success,
      ),
    );

    Navigator.pop(context, true);
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? hint,
    String? suffixText,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
    TextInputAction? textInputAction,
    VoidCallback? onSubmitted,
  }) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      enabled: !carregando,
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

  Widget seletorEntregador() {
    final theme = Theme.of(context);

    if (carregandoEntregadores) {
      return Container(
        height: 58,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    if (entregadores.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nenhum entregador vinculado',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Vincule um entregador antes de cadastrar uma entrega.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: entregadorSelecionado,
      dropdownColor: theme.cardColor,
      isExpanded: true,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: const InputDecoration(
        labelText: 'Entregador responsável',
        prefixIcon: Icon(Icons.delivery_dining),
      ),
      items: entregadores.map((entregador) {
        final nome = entregador['nome']?.toString().trim() ?? 'Entregador';

        final email = entregador['email']?.toString().trim() ?? '';

        return DropdownMenuItem<String>(
          value: email,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (email.isNotEmpty)
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
      onChanged: carregando
          ? null
          : (valor) {
              setState(() {
                entregadorSelecionado = valor;
              });
            },
    );
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

                seletorEntregador(),

                const SizedBox(height: 18),

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
                          onPressed: carregando ? null : buscarCep,
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
                  hint: 'Rua, número, bairro, cidade',
                  icon: Icons.location_on_outlined,
                  textCapitalization: TextCapitalization.words,
                ),

                const SizedBox(height: 6),

                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Após buscar o CEP, complete o endereço com o número e complemento.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
                  hint: 'Ex: Casa azul, deixar na portaria...',
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
              onPressed:
                  carregando || carregandoEntregadores || entregadores.isEmpty
                  ? null
                  : cadastrarEntrega,
              icon: carregando
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
                carregando ? 'Cadastrando...' : 'Cadastrar Entrega',
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
