import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/configuracoes_service.dart';
import '../theme/app_colors.dart';

class VeiculoConfiguracoesPage extends StatefulWidget {
  const VeiculoConfiguracoesPage({super.key});

  @override
  State<VeiculoConfiguracoesPage> createState() =>
      _VeiculoConfiguracoesPageState();
}

class _VeiculoConfiguracoesPageState extends State<VeiculoConfiguracoesPage> {
  String veiculoSelecionado = 'Moto';

  final consumoController = TextEditingController();
  final precoController = TextEditingController();
  final capacidadeController = TextEditingController();

  bool salvando = false;

  final Map<String, String> capacidadesPadrao = {
    'Moto': '20',
    'Hatch': '350',
    'Sedan': '450',
    'SUV': '600',
    'Pickup': '1000',
    'Van': '1500',
    'Caminhão Pequeno': '3500',
    'Caminhão Grande': '12000',
  };

  @override
  void initState() {
    super.initState();
    carregarConfiguracoes();
  }

  Future<void> carregarConfiguracoes() async {
    final veiculo = await ConfiguracoesService.buscarVeiculo();
    final capacidade = await ConfiguracoesService.buscarCapacidade();
    final consumo = await ConfiguracoesService.buscarConsumoMedio();
    final preco = await ConfiguracoesService.buscarPrecoCombustivel();

    if (!mounted) return;

    setState(() {
      veiculoSelecionado = veiculo ?? 'Moto';

      capacidadeController.text =
          capacidade ?? capacidadesPadrao[veiculoSelecionado] ?? '20';

      consumoController.text = consumo ?? '';
      precoController.text = preco ?? '';
    });
  }

  void atualizarCapacidade(String veiculo) {
    setState(() {
      veiculoSelecionado = veiculo;

      if (capacidadeController.text.isEmpty ||
          capacidadesPadrao.values.contains(capacidadeController.text.trim())) {
        capacidadeController.text = capacidadesPadrao[veiculo] ?? '20';
      }
    });
  }

  double? converterDecimal(String valor) {
    return double.tryParse(valor.trim().replaceAll(',', '.'));
  }

  Future<void> salvarConfiguracoes() async {
    if (salvando) return;

    final capacidadeTexto = capacidadeController.text.trim();

    final consumoTexto = consumoController.text.trim();

    final precoTexto = precoController.text.trim();

    final capacidade = double.tryParse(capacidadeTexto.replaceAll(',', '.'));

    if (capacidade == null || capacidade <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe uma capacidade de carga válida')),
      );
      return;
    }

    final consumo = converterDecimal(consumoTexto);

    if (consumoTexto.isNotEmpty && (consumo == null || consumo <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um consumo médio válido')),
      );
      return;
    }

    final preco = converterDecimal(precoTexto);

    if (precoTexto.isNotEmpty && (preco == null || preco <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um preço de combustível válido')),
      );
      return;
    }

    setState(() {
      salvando = true;
    });

    final capacidadeNormalizada = capacidade.toStringAsFixed(
      capacidade % 1 == 0 ? 0 : 2,
    );

    final consumoNormalizado = consumo == null ? '' : consumo.toString();

    final precoNormalizado = preco == null ? '' : preco.toString();

    await ConfiguracoesService.salvarConfiguracoes(
      veiculo: veiculoSelecionado,
      capacidade: capacidadeNormalizada,
      consumoMedio: consumoNormalizado,
      precoCombustivel: precoNormalizado,
    );

    final sucessoBackend = await AuthService.atualizarConfiguracoesVeiculo(
      veiculo: veiculoSelecionado,
      capacidadeCarga: capacidadeNormalizada,
    );

    if (!mounted) return;

    setState(() {
      salvando = false;

      capacidadeController.text = capacidadeNormalizada;

      consumoController.text = consumoNormalizado;

      precoController.text = precoNormalizado;
    });

    if (!sucessoBackend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'As configurações foram salvas no aparelho, '
            'mas não foi possível atualizar o servidor.',
          ),
        ),
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configurações salvas com sucesso'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  String textoVeiculo(String veiculo) {
    final capacidade = capacidadesPadrao[veiculo] ?? '';

    return '$veiculo ($capacidade kg)';
  }

  Widget secao({
    required String titulo,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              theme.brightness == Brightness.dark ? 0.16 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.14),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? suffixText,
  }) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      enabled: !salvando,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
        hintText: hint,
        suffixText: suffixText,
      ),
    );
  }

  @override
  void dispose() {
    consumoController.dispose();
    precoController.dispose();
    capacidadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Veículo e Combustível'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          secao(
            titulo: 'Veículo',
            icon: Icons.directions_car,
            children: [
              DropdownButtonFormField<String>(
                value: veiculoSelecionado,
                dropdownColor: theme.cardColor,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.directions_car),
                  labelText: 'Tipo de veículo',
                ),
                items: capacidadesPadrao.keys.map((veiculo) {
                  return DropdownMenuItem<String>(
                    value: veiculo,
                    child: Text(textoVeiculo(veiculo)),
                  );
                }).toList(),
                onChanged: salvando
                    ? null
                    : (valor) {
                        if (valor == null) return;

                        atualizarCapacidade(valor);
                      },
              ),

              const SizedBox(height: 16),

              campo(
                controller: capacidadeController,
                label: 'Capacidade de carga',
                hint: 'Ex: 20',
                icon: Icons.inventory_2,
                suffixText: 'kg',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),

          secao(
            titulo: 'Combustível',
            icon: Icons.local_gas_station,
            children: [
              campo(
                controller: consumoController,
                label: 'Consumo médio',
                hint: 'Ex: 35',
                icon: Icons.local_gas_station,
                suffixText: 'km/l',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),

              const SizedBox(height: 16),

              campo(
                controller: precoController,
                label: 'Preço do combustível',
                hint: 'Ex: 6,29',
                icon: Icons.attach_money,
                suffixText: 'R\$/L',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ],
          ),

          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: salvando ? null : salvarConfiguracoes,
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
              label: Text(salvando ? 'Salvando...' : 'Salvar Configurações'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
