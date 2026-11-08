import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/entrega_model.dart';
import '../providers/entregas_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

import 'cadastrar_entrega_manual_page.dart';
import 'finalizar_entrega_page.dart';
import 'ocr_page.dart';
import 'scanner_page.dart';

class EntregasPage extends StatefulWidget {
  const EntregasPage({super.key});

  @override
  State<EntregasPage> createState() => _EntregasPageState();
}

class _EntregasPageState extends State<EntregasPage> {
  final TextEditingController pesquisaController = TextEditingController();
  String filtro = 'todas';

  @override
  void dispose() {
    pesquisaController.dispose();
    super.dispose();
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

  List<MapEntry<int, EntregaModel>> filtrarEntregas(EntregasProvider provider) {
    final pesquisa = pesquisaController.text.trim().toLowerCase();
    return provider.entregas.asMap().entries.where((item) {
      final entrega = item.value;
      final status = entrega.status.toUpperCase();
      if (status == 'CANCELADA') return false;
      final correspondePesquisa =
          pesquisa.isEmpty ||
          entrega.cliente.toLowerCase().contains(pesquisa) ||
          entrega.endereco.toLowerCase().contains(pesquisa) ||
          (entrega.id?.toString() ?? '').contains(pesquisa);
      final correspondeFiltro =
          filtro == 'todas' ||
          (filtro == 'pendentes' && status == 'PENDENTE') ||
          (filtro == 'em_rota' && status == 'EM_ROTA') ||
          (filtro == 'entregues' && status == 'ENTREGUE') ||
          (filtro == 'nao_entregues' && status == 'NAO_ENTREGUE');
      return correspondePesquisa && correspondeFiltro;
    }).toList();
  }

  Widget chipFiltro(String valor, String texto, IconData icone) {
    final selecionado = filtro == valor;
    final theme = Theme.of(context);
    return ChoiceChip(
      selected: selecionado,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icone,
            size: 16,
            color: selecionado
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(texto),
        ],
      ),
      selectedColor: AppColors.primary,
      backgroundColor: theme.cardColor,
      labelStyle: TextStyle(
        color: selecionado ? Colors.white : theme.colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selecionado
              ? AppColors.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      onSelected: (_) => setState(() => filtro = valor),
    );
  }

  Widget badgeStatus(String status) {
    final cor = corStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconeStatus(status), color: cor, size: 15),
          const SizedBox(width: 4),
          Text(
            textoStatus(status),
            style: TextStyle(
              color: cor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      Provider.of<EntregasProvider>(
        context,
        listen: false,
      ).carregarEntregasDoBackend();
    });
  }

  Future<void> adicionarEntregaManual() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CadastrarEntregaManualPage(),
      ),
    );

    if (resultado == null) return;

    final entregasProvider = Provider.of<EntregasProvider>(
      context,
      listen: false,
    );

    await entregasProvider.adicionarEntrega(resultado as EntregaModel);
  }

  Future<void> escanearQRCode() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerPage()),
    );

    if (resultado == null) return;

    final entrega = await ApiService.buscarEntrega(resultado.toString());

    if (entrega == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entrega não encontrada')));

      return;
    }

    final entregasProvider = Provider.of<EntregasProvider>(
      context,
      listen: false,
    );

    await entregasProvider.adicionarEntrega(
      EntregaModel.fromJson(Map<String, dynamic>.from(entrega)),
    );
  }

  Future<void> lerEtiqueta() async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OcrPage()),
    );

    if (resultado == null) return;

    final entregasProvider = Provider.of<EntregasProvider>(
      context,
      listen: false,
    );

    await entregasProvider.adicionarEntrega(
      EntregaModel(
        endereco: resultado.toString(),
        cliente: 'Lido por OCR',
        valor: 0.0,
        observacao: 'Texto extraído da etiqueta',
      ),
    );
  }

  Future<void> finalizarEntrega(
    EntregaModel entrega,
    EntregasProvider provider,
  ) async {
    if (entrega.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta entrega não possui ID e não pode ser finalizada.',
          ),
        ),
      );

      return;
    }

    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FinalizarEntregaPage(
          entregaId: entrega.id!,
          cliente: entrega.cliente,
          endereco: entrega.endereco,
        ),
      ),
    );

    if (!mounted) return;

    if (resultado == true) {
      await provider.carregarEntregasDoBackend();
    }
  }

  Future<void> confirmarExclusao(
    int indexOriginal,
    EntregasProvider provider,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remover entrega'),
          content: const Text('Deseja realmente remover esta entrega?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Remover'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    final sucesso = await provider.removerEntrega(indexOriginal);

    if (!mounted) return;

    if (sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrega removida com sucesso'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível remover a entrega'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Color corStatus(String status) {
    switch (status) {
      case 'ENTREGUE':
        return AppColors.success;

      case 'EM_ROTA':
        return Colors.blue;

      case 'NAO_ENTREGUE':
        return AppColors.error;

      case 'CANCELADA':
        return Colors.grey;

      case 'PENDENTE':
      default:
        return AppColors.warning;
    }
  }

  String textoStatus(String status) {
    switch (status) {
      case 'ENTREGUE':
        return 'Entregue';

      case 'EM_ROTA':
        return 'Em rota';

      case 'NAO_ENTREGUE':
        return 'Não entregue';

      case 'CANCELADA':
        return 'Cancelada';

      case 'PENDENTE':
      default:
        return 'Pendente';
    }
  }

  IconData iconeStatus(String status) {
    switch (status) {
      case 'ENTREGUE':
        return Icons.check_circle;

      case 'EM_ROTA':
        return Icons.local_shipping;

      case 'NAO_ENTREGUE':
        return Icons.report_problem;

      case 'CANCELADA':
        return Icons.cancel;

      case 'PENDENTE':
      default:
        return Icons.schedule;
    }
  }

  Widget botaoTopo({
    required IconData icon,
    required String texto,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 86,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                texto,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget cardEntrega(
    EntregaModel entrega,
    int indexOriginal,
    EntregasProvider provider,
  ) {
    final theme = Theme.of(context);
    final status = entrega.status.toUpperCase();
    final cor = corStatus(status);
    final podeFinalizar = status == 'PENDENTE' || status == 'EM_ROTA';
    final podeExcluir = status == 'PENDENTE';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withOpacity(0.14),
                  child: const Icon(
                    Icons.inventory_2,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entrega.cliente.isEmpty
                        ? 'Cliente não informado'
                        : entrega.cliente,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                badgeStatus(status),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 19,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entrega.endereco,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            if (entrega.complemento.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.home_outlined,
                    size: 19,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entrega.complemento,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (entrega.observacao.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notes,
                    size: 19,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entrega.observacao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.attach_money,
                  size: 19,
                  color: AppColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  'R\$ ${entrega.valor.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  'ID #${entrega.id ?? '-'}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    podeFinalizar
                        ? 'Aguardando finalização'
                        : textoStatus(status),
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (podeExcluir)
                  IconButton(
                    tooltip: 'Remover entrega',
                    onPressed: () => confirmarExclusao(indexOriginal, provider),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (podeFinalizar)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => finalizarEntrega(entrega, provider),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text(
                    'Finalizar entrega',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 48,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cor.withOpacity(0.22)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(iconeStatus(status), color: cor),
                    const SizedBox(width: 8),
                    Text(
                      textoStatus(status),
                      style: TextStyle(color: cor, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntregasProvider>();
    final theme = Theme.of(context);
    final lista = filtrarEntregas(provider);

    return Scaffold(
      appBar: AppBar(title: const Text('Minhas Entregas'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: provider.carregarEntregasDoBackend,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                botaoTopo(
                  icon: Icons.qr_code_scanner,
                  texto: 'QR Code',
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  onTap: escanearQRCode,
                ),
                const SizedBox(width: 10),
                botaoTopo(
                  icon: Icons.document_scanner,
                  texto: 'Etiqueta',
                  color: Colors.deepPurpleAccent,
                  onTap: lerEtiqueta,
                ),
                const SizedBox(width: 10),
                botaoTopo(
                  icon: Icons.add_location_alt,
                  texto: 'Manual',
                  color: AppColors.primary,
                  onTap: adicionarEntregaManual,
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: pesquisaController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por cliente, endereço ou ID',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: pesquisaController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          pesquisaController.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  chipFiltro('todas', 'Todas', Icons.list),
                  const SizedBox(width: 8),
                  chipFiltro('pendentes', 'Pendentes', Icons.pending),
                  const SizedBox(width: 8),
                  chipFiltro('em_rota', 'Em rota', Icons.local_shipping),
                  const SizedBox(width: 8),
                  chipFiltro('entregues', 'Entregues', Icons.check_circle),
                  const SizedBox(width: 8),
                  chipFiltro(
                    'nao_entregues',
                    'Não entregues',
                    Icons.report_problem,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (provider.carregando)
              const Padding(
                padding: EdgeInsets.only(top: 90),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (lista.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 58,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Nenhuma entrega encontrada',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...lista.map(
                (item) => cardEntrega(item.value, item.key, provider),
              ),
          ],
        ),
      ),
    );
  }
}
