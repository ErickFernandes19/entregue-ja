import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../services/cep_service.dart';
import '../services/empresa_entrega_service.dart';
import '../services/empresa_lista_entregas_service.dart';
import '../services/empresa_service.dart';
import '../services/geocoding_service.dart';
import '../theme/app_colors.dart';

class CadastrarEntregaPage extends StatefulWidget {
  const CadastrarEntregaPage({super.key});

  @override
  State<CadastrarEntregaPage> createState() => _CadastrarEntregaPageState();
}

class _CadastrarEntregaPageState extends State<CadastrarEntregaPage> {
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
    try {
      final lista = await EmpresaService.buscarEntregadores();
      if (!mounted) return;
      setState(() {
        entregadores = lista;
        entregadorSelecionado = null;
      });
    } catch (e) {
      debugPrint('Erro ao carregar entregadores: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível carregar os entregadores.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          carregandoEntregadores = false;
        });
      }
    }
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

    setState(() {
      ruaController.text = logradouro;
      bairroController.text = bairro;
      cidadeController.text = cidade;
      ufController.text = uf;
      numeroController.clear();
      complementoController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Endereço encontrado. Informe o número.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  String montarEnderecoCompleto() {
    final cep = cepController.text.replaceAll(RegExp(r'[^0-9]'), '').trim();

    final rua = ruaController.text.trim();
    final numero = numeroController.text.trim();
    final bairro = bairroController.text.trim();
    final cidade = cidadeController.text.trim();
    final uf = ufController.text.trim();

    final partes = <String>[];

    if (rua.isNotEmpty) {
      if (numero.isNotEmpty) {
        partes.add('$rua, $numero');
      } else {
        partes.add(rua);
      }
    }

    if (bairro.isNotEmpty) {
      partes.add(bairro);
    }

    if (cidade.isNotEmpty && uf.isNotEmpty) {
      partes.add('$cidade - $uf');
    } else if (cidade.isNotEmpty) {
      partes.add(cidade);
    } else if (uf.isNotEmpty) {
      partes.add(uf);
    }

    if (cep.length == 8) {
      final cepFormatado = '${cep.substring(0, 5)}-${cep.substring(5)}';

      partes.add(cepFormatado);
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

  double? converterValor(String texto) {
    return double.tryParse(texto.trim().replaceAll(',', '.'));
  }

  String normalizarEndereco(String texto) {
    const origem = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const destino = 'aaaaaeeeeiiiiooooouuuucn';
    var resultado = texto.toLowerCase().trim();
    for (var i = 0; i < origem.length; i++) {
      resultado = resultado.replaceAll(origem[i], destino[i]);
    }
    return resultado.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool entregaAtiva(Map<String, dynamic> entrega) {
    final status = (entrega['status'] ?? '').toString().trim().toUpperCase();
    final entregue =
        entrega['entregue'] == true ||
        entrega['entregue']?.toString().toLowerCase() == 'true';
    return !entregue &&
        (status == 'PENDENTE' ||
            status == 'EM_ROTA' ||
            (status.isEmpty && !entregue));
  }

  double? numeroCoordenada(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '');
  }

  Map<String, double>? coordenadasExistentes(Map<String, dynamic> entrega) {
    final latitude = numeroCoordenada(entrega['latitude']);
    final longitude = numeroCoordenada(entrega['longitude']);
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        (latitude == 0 && longitude == 0)) {
      return null;
    }
    return {'lat': latitude, 'lng': longitude};
  }

  Future<bool> confirmarEnderecoDuplicado(
    int quantidade,
    String endereco,
  ) async {
    final resposta = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Endereço com entregas ativas'),
        content: Text(
          'Já ${quantidade == 1 ? 'existe 1 entrega ativa' : 'existem $quantidade entregas ativas'} '
          'neste endereço:\n\n$endereco\n\n'
          'A contagem considera todas as entregas da empresa, inclusive '
          'as atribuídas a outros entregadores. '
          'Deseja cadastrar outra entrega neste local?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar cadastro'),
          ),
        ],
      ),
    );
    return resposta == true;
  }

  Future<void> cadastrarEntrega() async {
    if (carregando) return;

    final cliente = clienteController.text.trim();
    final rua = ruaController.text.trim();
    final numero = numeroController.text.trim();
    final bairro = bairroController.text.trim();
    final cidade = cidadeController.text.trim();
    final uf = ufController.text.trim();
    final complemento = complementoController.text.trim();
    final observacao = observacaoController.text.trim();

    final valor = converterValor(valorController.text);

    if (cliente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do cliente')),
      );
      return;
    }

    if (cepController.text.replaceAll(RegExp(r'[^0-9]'), '').length != 8) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe um CEP válido')));
      return;
    }

    if (rua.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe a rua da entrega')));
      return;
    }

    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o número do endereço')),
      );
      return;
    }

    if (bairro.isEmpty || cidade.isEmpty || uf.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete bairro, cidade e estado')),
      );
      return;
    }

    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido para a entrega')),
      );
      return;
    }

    setState(() {
      carregando = true;
    });

    try {
      final endereco = montarEnderecoCompleto();
      final enderecoNormalizado = normalizarEndereco(endereco);
      final enderecoParaMapa = montarEnderecoParaMapa();
      final entregadorEmail = entregadorSelecionado;

      final lista = await EmpresaListaEntregasService.buscarEntregas();
      if (!mounted) return;

      final mesmoEndereco = <Map<String, dynamic>>[];
      for (final item in lista) {
        if (item is! Map) continue;
        final entrega = Map<String, dynamic>.from(item);
        if (normalizarEndereco((entrega['endereco'] ?? '').toString()) ==
            enderecoNormalizado) {
          mesmoEndereco.add(entrega);
        }
      }

      final quantidadeAtivas = mesmoEndereco.where(entregaAtiva).length;
      if (quantidadeAtivas > 0) {
        final confirmado = await confirmarEnderecoDuplicado(
          quantidadeAtivas,
          endereco,
        );
        if (!mounted || !confirmado) return;
      }

      Map<String, double>? coordenadas;
      for (final entrega in mesmoEndereco) {
        coordenadas = coordenadasExistentes(entrega);
        if (coordenadas != null) break;
      }

      coordenadas ??= await GeocodingService.buscarCoordenadas(
        enderecoParaMapa,
      );
      if (coordenadas == null) {
        final cep = cepController.text.replaceAll(RegExp(r'[^0-9]'), '').trim();
        final enderecoAlternativo = '$cep, $numero, $cidade - $uf';
        coordenadas = await GeocodingService.buscarCoordenadas(
          enderecoAlternativo,
        );
      }
      if (!mounted) return;

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

      final resultado = await EmpresaEntregaService.cadastrarEntrega(
        empresaEmail: empresaEmail,
        entregadorEmail: entregadorEmail,
        cliente: cliente,
        endereco: endereco,
        complemento: complemento,
        valor: valor,
        observacao: observacao,
        latitude: coordenadas?['lat'],
        longitude: coordenadas?['lng'],
      );
      if (!mounted) return;
      if (resultado == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível cadastrar a entrega'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrega cadastrada com sucesso'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop(true);
    } catch (e) {
      debugPrint('Erro ao verificar duplicidade/cadastrar entrega: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível verificar as entregas ou concluir o cadastro. Tente novamente.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
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
      return const SizedBox(
        height: 58,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final disponiveis = entregadores.where((entregador) {
      return (entregador['email']?.toString().trim() ?? '').isNotEmpty;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: entregadorSelecionado,
          dropdownColor: theme.cardColor,
          isExpanded: true,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: const InputDecoration(
            labelText: 'Entregador responsável (opcional)',
            prefixIcon: Icon(Icons.delivery_dining),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Sem entregador — atribuir depois'),
            ),
            ...disponiveis.map((entregador) {
              final nome =
                  entregador['nome']?.toString().trim() ?? 'Entregador';
              final email = entregador['email']!.toString().trim();
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
            }),
          ],
          onChanged: carregando
              ? null
              : (valor) {
                  setState(() {
                    entregadorSelecionado = valor;
                  });
                },
        ),
        if (disponiveis.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Nenhum entregador vinculado. Você pode cadastrar a entrega e atribuir depois.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.14,
                      ),
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
              onPressed: carregando || carregandoEntregadores
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
