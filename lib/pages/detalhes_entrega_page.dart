import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/empresa_lista_entregas_service.dart';
import '../theme/app_colors.dart';
import 'editar_entrega_page.dart';

class DetalhesEntregaPage extends StatelessWidget {
  final Map<String, dynamic> entrega;

  const DetalhesEntregaPage({super.key, required this.entrega});

  String statusEntrega() {
    final status = (entrega['status'] ?? '').toString();

    if (status.isNotEmpty) {
      return status;
    }

    final entregue = entrega['entregue'] == true;

    return entregue ? 'ENTREGUE' : 'PENDENTE';
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

  Future<void> cancelarEntrega(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar entrega'),
          content: const Text('Tem certeza que deseja cancelar esta entrega?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Não'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sim, cancelar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    final sucesso = await EmpresaListaEntregasService.cancelarEntrega(
      entrega['id'],
    );

    if (!context.mounted) return;

    if (sucesso) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entrega cancelada')));

      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao cancelar entrega')));
    }
  }

  Widget linhaInformacao({
    required BuildContext context,
    required IconData icon,
    required String titulo,
    required String valor,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withOpacity(0.14),
            child: Icon(icon, size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget badgeStatus(String status) {
    final cor = corStatus(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconeStatus(status), size: 17, color: cor),
          const SizedBox(width: 5),
          Text(
            textoStatus(status),
            style: TextStyle(color: cor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final status = statusEntrega();

    final cliente = entrega['cliente']?.toString() ?? '';

    final endereco = entrega['endereco']?.toString() ?? '';

    final observacao = entrega['observacao']?.toString() ?? '';

    final valor = (entrega['valor'] as num?)?.toDouble() ?? 0.0;

    final id = entrega['id'];

    final podeEditar = status == 'PENDENTE';

    final podeCancelar = status == 'PENDENTE' || status == 'EM_ROTA';

    return Scaffold(
      appBar: AppBar(title: Text('Entrega #$id'), centerTitle: true),
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
                    theme.brightness == Brightness.dark ? 0.16 : 0.05,
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
                      radius: 25,
                      backgroundColor: AppColors.primary.withOpacity(0.14),
                      child: const Icon(
                        Icons.inventory_2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        cliente.isEmpty ? 'Cliente não informado' : cliente,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                linhaInformacao(
                  context: context,
                  icon: Icons.location_on_outlined,
                  titulo: 'Endereço',
                  valor: endereco.isEmpty ? 'Não informado' : endereco,
                ),

                linhaInformacao(
                  context: context,
                  icon: Icons.attach_money,
                  titulo: 'Valor',
                  valor: 'R\$ ${valor.toStringAsFixed(2)}',
                ),

                if (observacao.isNotEmpty)
                  linhaInformacao(
                    context: context,
                    icon: Icons.notes,
                    titulo: 'Observação',
                    valor: observacao,
                  ),

                const SizedBox(height: 4),

                badgeStatus(status),
              ],
            ),
          ),

          const SizedBox(height: 18),

          if (podeEditar)
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final atualizado = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditarEntregaPage(entrega: entrega),
                    ),
                  );

                  if (atualizado == true && context.mounted) {
                    Navigator.pop(context, true);
                  }
                },
                icon: const Icon(Icons.edit),
                label: const Text('Editar Entrega'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          if (podeEditar) const SizedBox(height: 12),

          if (podeCancelar)
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  cancelarEntrega(context);
                },
                icon: const Icon(Icons.cancel),
                label: const Text('Cancelar Entrega'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.35),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'QR Code da Entrega',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: QrImageView(
                    data: id.toString(),
                    size: 230,
                    backgroundColor: Colors.white,
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  'ID: $id',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
