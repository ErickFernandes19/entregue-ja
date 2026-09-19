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

    await provider.removerEntrega(indexOriginal);
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

    final status = entrega.status;
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
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                  radius: 18,
                  backgroundColor: AppColors.primary.withOpacity(0.14),
                  child: const Icon(
                    Icons.location_on,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entrega.endereco,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entrega.cliente,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                Icon(
                  Icons.attach_money,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'R\$ ${entrega.valor.toStringAsFixed(2)}',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ],
            ),

            if (entrega.observacao.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notes,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entrega.observacao,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(iconeStatus(status), size: 16, color: cor),
                      const SizedBox(width: 5),
                      Text(
                        textoStatus(status),
                        style: TextStyle(
                          color: cor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                IconButton(
                  tooltip: 'Excluir',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  onPressed: podeExcluir
                      ? () async {
                          await confirmarExclusao(indexOriginal, provider);
                        }
                      : null,
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (podeFinalizar)
              SizedBox(
                height: 48,
                width: double.infinity,
                child: ElevatedButton.icon(
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
                  onPressed: () async {
                    await finalizarEntrega(entrega, provider);
                  },
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
    final entregasProvider = Provider.of<EntregasProvider>(context);

    final theme = Theme.of(context);

    final entregasVisiveis = entregasProvider.entregas
        .asMap()
        .entries
        .where((entry) => entry.value.status != 'CANCELADA')
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Entregas'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: entregasProvider.carregarEntregasDoBackend,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
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

              Expanded(
                child: entregasProvider.carregando
                    ? const Center(child: CircularProgressIndicator())
                    : entregasVisiveis.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 60,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              'Nenhuma entrega adicionada ainda',
                              style: TextStyle(
                                fontSize: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: entregasVisiveis.length,
                        itemBuilder: (context, index) {
                          final item = entregasVisiveis[index];

                          return cardEntrega(
                            item.value,
                            item.key,
                            entregasProvider,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
