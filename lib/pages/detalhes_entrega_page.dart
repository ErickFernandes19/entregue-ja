import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/empresa_lista_entregas_service.dart';
import '../services/entrega_service.dart';
import '../theme/app_colors.dart';
import 'editar_entrega_page.dart';

class DetalhesEntregaPage extends StatefulWidget {
  final Map<String, dynamic> entrega;

  const DetalhesEntregaPage({super.key, required this.entrega});

  @override
  State<DetalhesEntregaPage> createState() => _DetalhesEntregaPageState();
}

class _DetalhesEntregaPageState extends State<DetalhesEntregaPage> {
  Uint8List? bytesComprovante;

  bool carregandoComprovante = false;
  bool erroComprovante = false;

  Map<String, dynamic> get entrega => widget.entrega;

  String statusEntrega() {
    final status = (entrega['status'] ?? '').toString().trim();

    if (status.isNotEmpty) {
      return status;
    }

    return entrega['entregue'] == true ? 'ENTREGUE' : 'PENDENTE';
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
      default:
        return Icons.schedule;
    }
  }

  String get idEntrega => (entrega['id'] ?? '').toString();

  String get referenciaComprovante =>
      (entrega['fotoComprovante'] ?? '').toString().trim();

  bool get possuiComprovante =>
      idEntrega.isNotEmpty && referenciaComprovante.isNotEmpty;

  String get motivoNaoEntrega =>
      (entrega['motivoNaoEntrega'] ?? '').toString().trim();

  String get justificativaNaoEntrega =>
      (entrega['justificativa'] ?? '').toString().trim();

  String descricaoMotivo(String motivo) {
    const motivos = {
      'DESTINATARIO_AUSENTE': 'Destinatário ausente',
      'LOCAL_FECHADO': 'Local fechado',
      'ENDERECO_NAO_LOCALIZADO': 'Endereço não localizado',
      'DESTINATARIO_RECUSOU': 'Destinatário recusou a entrega',
      'ACESSO_NAO_PERMITIDO': 'Acesso ao local não permitido',
      'OUTRO': 'Outro motivo',
    };

    return motivos[motivo] ??
        (motivo.isEmpty ? 'Motivo não informado' : motivo);
  }

  @override
  void initState() {
    super.initState();

    if (possuiComprovante) {
      carregarComprovante();
    }
  }

  Future<void> carregarComprovante() async {
    if (!possuiComprovante || carregandoComprovante) {
      return;
    }

    setState(() {
      carregandoComprovante = true;
      erroComprovante = false;
    });

    try {
      final bytes = await EntregaService.buscarBytesComprovante(
        idEntrega: idEntrega,
        referencia: referenciaComprovante,
        empresa: true,
      );

      if (!mounted) return;

      setState(() {
        bytesComprovante = bytes;
        erroComprovante = bytes == null || bytes.isEmpty;
      });
    } catch (e) {
      debugPrint('Erro ao carregar comprovante: $e');

      if (!mounted) return;

      setState(() {
        erroComprovante = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          carregandoComprovante = false;
        });
      }
    }
  }

  void ampliarComprovante() {
    final bytes = bytesComprovante;

    if (bytes == null || bytes.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Comprovante da entrega',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> cancelarEntrega() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancelar entrega'),
          content: const Text('Tem certeza que deseja cancelar esta entrega?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Não'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
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

    if (confirmar != true) return;

    final sucesso = await EmpresaListaEntregasService.cancelarEntrega(
      entrega['id'],
    );

    if (!mounted) return;

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

  Widget secaoNaoEntrega() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.report_problem_outlined,
                color: AppColors.error,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Detalhes da não entrega',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            'Motivo informado',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            descricaoMotivo(motivoNaoEntrega),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 18),

          Divider(color: theme.colorScheme.outlineVariant),

          const SizedBox(height: 12),

          Text(
            'Justificativa do entregador',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.65),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              justificativaNaoEntrega.isEmpty
                  ? 'Justificativa não informada.'
                  : justificativaNaoEntrega,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget secaoComprovante() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Comprovante fotográfico',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (carregandoComprovante)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (bytesComprovante != null && bytesComprovante!.isNotEmpty)
            Column(
              children: [
                InkWell(
                  onTap: ampliarComprovante,
                  borderRadius: BorderRadius.circular(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      bytesComprovante!,
                      height: 230,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: ampliarComprovante,
                  icon: const Icon(Icons.zoom_in),
                  label: const Text('Ampliar comprovante'),
                ),
              ],
            )
          else if (erroComprovante)
            Column(
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  size: 42,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Não foi possível carregar o comprovante.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: carregarComprovante,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ],
            )
          else
            const Text('Nenhum comprovante disponível.'),
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

    final statusComComprovante =
        status == 'ENTREGUE' || status == 'NAO_ENTREGUE';

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
                  icon: Icons.location_on_outlined,
                  titulo: 'Endereço',
                  valor: endereco.isEmpty ? 'Não informado' : endereco,
                ),

                linhaInformacao(
                  icon: Icons.attach_money,
                  titulo: 'Valor',
                  valor: 'R\$ ${valor.toStringAsFixed(2)}',
                ),

                if (observacao.isNotEmpty)
                  linhaInformacao(
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
                onPressed: cancelarEntrega,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancelar Entrega'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          if (status == 'NAO_ENTREGUE') ...[
            const SizedBox(height: 18),
            secaoNaoEntrega(),
          ],

          if (statusComComprovante) ...[
            const SizedBox(height: 18),
            secaoComprovante(),
          ],

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
