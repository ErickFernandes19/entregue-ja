import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
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
  bool carregando = true;
  String? erroCarregamento;
  String? erroSincronizacao;
  int versaoCarregamento = 0;

  bool get bloqueado => salvando || carregando || erroCarregamento != null;

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

  void mostrarMensagem(String mensagem, {bool sucesso = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: sucesso ? AppColors.success : null,
        ),
      );
  }

  Future<void> carregarConfiguracoes() async {
    if (salvando) return;

    setState(() {
      carregando = true;
      erroCarregamento = null;
    });

    try {
      final veiculo = await ConfiguracoesService.buscarVeiculo();
      final capacidade = await ConfiguracoesService.buscarCapacidade();
      final consumo = await ConfiguracoesService.buscarConsumoMedio();
      final preco = await ConfiguracoesService.buscarPrecoCombustivel();

      if (!mounted) return;

      final veiculoConhecido =
          veiculo == null || capacidadesPadrao.containsKey(veiculo);

      setState(() {
        veiculoSelecionado = veiculoConhecido ? veiculo ?? 'Moto' : 'Moto';
        capacidadeController.text =
            capacidade ?? capacidadesPadrao[veiculoSelecionado] ?? '20';
        consumoController.text = consumo ?? '';
        precoController.text = preco ?? '';
        versaoCarregamento++;
      });

      if (!veiculoConhecido) {
        mostrarMensagem(
          'O tipo de veículo salvo não é reconhecido. Confira o veículo e '
          'a capacidade antes de salvar.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erroCarregamento = ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível carregar as configurações do veículo. '
              'Tente novamente.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  void atualizarCapacidade(String veiculo) {
    if (bloqueado) return;

    setState(() {
      veiculoSelecionado = veiculo;

      if (capacidadeController.text.isEmpty ||
          capacidadesPadrao.values.contains(capacidadeController.text.trim())) {
        capacidadeController.text = capacidadesPadrao[veiculo] ?? '20';
      }
    });
  }

  double? converterDecimal(String valor) {
    final numero = double.tryParse(valor.trim().replaceAll(',', '.'));
    if (numero == null || !numero.isFinite || numero <= 0) return null;
    return numero;
  }

  Future<void> salvarConfiguracoes() async {
    if (bloqueado) return;

    FocusScope.of(context).unfocus();

    final capacidadeTexto = capacidadeController.text.trim();
    final consumoTexto = consumoController.text.trim();
    final precoTexto = precoController.text.trim();

    final capacidade = converterDecimal(capacidadeTexto);
    if (capacidade == null) {
      mostrarMensagem(
        'Informe uma capacidade de carga válida, maior que zero.',
      );
      return;
    }

    final consumo = converterDecimal(consumoTexto);
    if (consumoTexto.isNotEmpty && consumo == null) {
      mostrarMensagem('Informe um consumo médio válido, maior que zero.');
      return;
    }

    final preco = converterDecimal(precoTexto);
    if (precoTexto.isNotEmpty && preco == null) {
      mostrarMensagem(
        'Informe um preço de combustível válido, maior que zero.',
      );
      return;
    }

    final capacidadeNormalizada = capacidade.toStringAsFixed(
      capacidade % 1 == 0 ? 0 : 2,
    );

    if (converterDecimal(capacidadeNormalizada) == null) {
      mostrarMensagem('Informe uma capacidade de carga de pelo menos 0,01 kg.');
      return;
    }

    final consumoNormalizado = consumo?.toString() ?? '';
    final precoNormalizado = preco?.toString() ?? '';
    final veiculo = veiculoSelecionado;
    var salvamentoLocalConcluido = false;

    setState(() => salvando = true);

    try {
      await ConfiguracoesService.salvarConfiguracoes(
        veiculo: veiculo,
        capacidade: capacidadeNormalizada,
        consumoMedio: consumoNormalizado,
        precoCombustivel: precoNormalizado,
      );
      salvamentoLocalConcluido = true;

      final sucessoBackend = await AuthService.atualizarConfiguracoesVeiculo(
        veiculo: veiculo,
        capacidadeCarga: capacidadeNormalizada,
        lancarErro: true,
      );

      if (!sucessoBackend) {
        throw const ApiException(
          'Não foi possível atualizar as configurações do veículo no servidor.',
        );
      }

      if (!mounted) return;

      setState(() {
        erroSincronizacao = null;
        capacidadeController.text = capacidadeNormalizada;
        consumoController.text = consumoNormalizado;
        precoController.text = precoNormalizado;
      });
      mostrarMensagem('Configurações salvas com sucesso!', sucesso: true);
    } catch (e) {
      if (!mounted) return;

      final mensagem = ApiService.mensagemErro(
        e,
        mensagemPadrao: salvamentoLocalConcluido
            ? 'Não foi possível atualizar o servidor. Tente salvar novamente.'
            : 'Não foi possível concluir o salvamento no aparelho. Tente novamente.',
      );

      if (salvamentoLocalConcluido) {
        final aviso =
            'As configurações foram salvas no aparelho, mas a '
            'sincronização com o servidor não foi confirmada. $mensagem';
        setState(() => erroSincronizacao = aviso);
        mostrarMensagem(aviso);
      } else {
        mostrarMensagem(mensagem);
      }
    } finally {
      if (mounted) {
        setState(() => salvando = false);
      }
    }
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
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.16 : 0.05,
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
                backgroundColor: AppColors.primary.withValues(alpha: 0.14),
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
      enabled: !bloqueado,
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

    return PopScope(
      canPop: !salvando,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: salvando
                ? null
                : () {
                    context.go('/entregador/inicio');
                  },
          ),
          title: const Text('Veículo e Combustível'),
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (carregando) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
            ],
            if (erroCarregamento != null) ...[
              Text(
                erroCarregamento!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              TextButton(
                onPressed: carregando ? null : carregarConfiguracoes,
                child: const Text('Tentar novamente'),
              ),
              const SizedBox(height: 12),
            ],
            if (erroSincronizacao != null) ...[
              Text(
                erroSincronizacao!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
            ],
            secao(
              titulo: 'Veículo',
              icon: Icons.directions_car,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(versaoCarregamento),
                  initialValue: veiculoSelecionado,
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
                  onChanged: bloqueado
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
                onPressed: bloqueado ? null : salvarConfiguracoes,
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
      ),
    );
  }
}
