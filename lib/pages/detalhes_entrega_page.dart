import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';
import '../services/empresa_entrega_service.dart';
import '../services/empresa_lista_entregas_service.dart';
import '../services/empresa_service.dart';
import '../services/entrega_service.dart';
import '../theme/app_colors.dart';

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
  bool atribuindoEntregador = false;
  Timer? _timerAcompanhamento;
  Map<String, dynamic>? _dadosAcompanhamento;
  Map<String, dynamic>? _localizacaoRecebida;
  bool _consultandoAcompanhamento = false;

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

    _dadosAcompanhamento = Map<String, dynamic>.from(widget.entrega);
    _timerAcompanhamento = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _atualizarAcompanhamento(),
    );
    unawaited(_atualizarAcompanhamento());

    if (possuiComprovante) {
      carregarComprovante();
    }
  }

  @override
  void dispose() {
    _timerAcompanhamento?.cancel();
    super.dispose();
  }

  double? _numeroCoordenada(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse((valor ?? '').toString().replaceAll(',', '.'));
  }

  LatLng? _coordenadaValida(dynamic latitude, dynamic longitude) {
    final lat = _numeroCoordenada(latitude);
    final lng = _numeroCoordenada(longitude);
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return null;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    if (lat == 0 && lng == 0) return null;
    return LatLng(lat, lng);
  }

  LatLng? get _localizacaoEntregador {
    final dados = _localizacaoRecebida;
    if (dados == null || dados['status'] != 'EM_ROTA') return null;
    return _coordenadaValida(dados['latitude'], dados['longitude']);
  }

  LatLng? get _localizacaoDestino {
    final dados = _dadosAcompanhamento ?? entrega;
    return _coordenadaValida(dados['latitude'], dados['longitude']);
  }

  DateTime? get _horarioLocalizacao {
    final valor = _localizacaoRecebida?['dataAtualizacao'];
    if (valor == null) return null;
    return DateTime.tryParse(valor.toString())?.toLocal();
  }

  Future<void> _atualizarAcompanhamento() async {
    if (_consultandoAcompanhamento || !mounted) return;
    if (statusEntrega() != 'EM_ROTA') return;
    final id = int.tryParse(idEntrega);
    if (id == null) return;
    _consultandoAcompanhamento = true;
    try {
      final dados = await ApiService.buscarLocalizacaoEntregador(id);
      if (!mounted) return;
      if (dados != null) {
        setState(() {
          _localizacaoRecebida = dados;
        });
        if (dados['status'] != 'EM_ROTA') {
          _timerAcompanhamento?.cancel();
        }
      }
    } catch (e) {
      debugPrint('Não foi possível consultar acompanhamento: $e');
    } finally {
      _consultandoAcompanhamento = false;
    }
  }

  Widget _secaoAcompanhamento() {
    final tema = Theme.of(context);
    final entregador = _localizacaoEntregador;
    final destino = _localizacaoDestino;
    final horario = _horarioLocalizacao;
    final recente =
        horario != null &&
        DateTime.now().difference(horario).inSeconds >= 0 &&
        DateTime.now().difference(horario) <= const Duration(seconds: 60);
    final pontos = <Marker>{};
    if (entregador != null) {
      pontos.add(
        Marker(
          markerId: const MarkerId('entregador'),
          position: entregador,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Localização do entregador'),
        ),
      );
    }
    if (destino != null) {
      pontos.add(
        Marker(
          markerId: const MarkerId('destino'),
          position: destino,
          infoWindow: const InfoWindow(title: 'Destino da entrega'),
        ),
      );
    }
    final centro = entregador ?? destino;
    String horarioTexto = 'Aguardando localização do entregador';
    if (horario != null) {
      String dois(int n) => n.toString().padLeft(2, '0');
      horarioTexto =
          'Última posição: ${dois(horario.hour)}:${dois(horario.minute)}:${dois(horario.second)}';
    } else if (entregador != null) {
      horarioTexto = 'Horário da posição não informado';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tema.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: tema.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_searching, color: AppColors.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Acompanhamento do entregador',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar localização',
                onPressed: _atualizarAcompanhamento,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            recente ? 'Localização recente' : horarioTexto,
            style: TextStyle(
              color: recente
                  ? AppColors.success
                  : tema.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (recente) ...[const SizedBox(height: 4), Text(horarioTexto)],
          const SizedBox(height: 12),
          if (centro == null)
            Container(
              height: 230,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: tema.colorScheme.surfaceContainerHighest,
              ),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'O mapa ficará disponível quando o servidor informar as coordenadas da entrega ou do entregador.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 260,
                child: GoogleMap(
                  key: ValueKey('${centro.latitude},${centro.longitude}'),
                  initialCameraPosition: CameraPosition(
                    target: centro,
                    zoom: 15,
                  ),
                  markers: pontos,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            entregador == null
                ? 'Aguardando o envio da posição pelo aplicativo do entregador.'
                : horario == null
                ? 'Posição recebida, mas sem horário para confirmar se é atual.'
                : recente
                ? 'O mapa consulta atualizações a cada 15 segundos.'
                : 'A última posição pode estar desatualizada.',
            style: TextStyle(color: tema.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
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

      context.pop(true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao cancelar entrega')));
    }
  }

  String nomeEntregador() {
    final responsavel = entrega['entregador'];
    if (responsavel is Map) {
      final nome = responsavel['nome']?.toString().trim() ?? '';
      if (nome.isNotEmpty) return nome;
      return responsavel['email']?.toString().trim() ?? '';
    }
    return '';
  }

  Future<void> atribuirEntregador() async {
    if (atribuindoEntregador) return;

    setState(() {
      atribuindoEntregador = true;
    });

    try {
      final lista = await EmpresaService.buscarEntregadores();
      if (!mounted) return;

      final disponiveis = lista.where((item) {
        if (item is! Map) return false;
        return (item['email']?.toString().trim() ?? '').isNotEmpty;
      }).toList();

      if (disponiveis.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhum entregador vinculado à empresa.'),
          ),
        );
        return;
      }

      String? selecionado;
      final email = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, atualizarDialogo) => AlertDialog(
            title: const Text('Atribuir entregador'),
            content: SizedBox(
              width: double.maxFinite,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selecionado,
                decoration: const InputDecoration(
                  labelText: 'Entregador responsável',
                  prefixIcon: Icon(Icons.delivery_dining),
                ),
                items: disponiveis.map((item) {
                  final nome = item['nome']?.toString().trim() ?? '';
                  final email = item['email'].toString().trim();
                  return DropdownMenuItem<String>(
                    value: email,
                    child: Text(
                      nome.isEmpty ? email : '$nome ($email)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (valor) {
                  atualizarDialogo(() {
                    selecionado = valor;
                  });
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: selecionado == null
                    ? null
                    : () => Navigator.pop(dialogContext, selecionado),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ),
      );

      if (!mounted || email == null) return;

      final id = int.tryParse(idEntrega);
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID da entrega inválido.')),
        );
        return;
      }

      final sucesso = await EmpresaEntregaService.atribuirEntregador(
        entregaId: id,
        entregadorEmail: email,
      );

      if (!mounted) return;

      if (sucesso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entregador atribuído com sucesso.'),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atribuir o entregador.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao atribuir entregador: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível carregar ou atribuir o entregador.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          atribuindoEntregador = false;
        });
      }
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
            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
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
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
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
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
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
              color: theme.colorScheme.surface.withValues(alpha: 0.65),
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
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.14,
                      ),
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

                linhaInformacao(
                  icon: Icons.delivery_dining,
                  titulo: 'Entregador responsável',
                  valor: nomeEntregador().isEmpty
                      ? 'Não atribuído'
                      : nomeEntregador(),
                ),

                const SizedBox(height: 4),
                badgeStatus(status),
              ],
            ),
          ),

          const SizedBox(height: 18),

          if (podeEditar && nomeEntregador().isEmpty)
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: atribuindoEntregador ? null : atribuirEntregador,
                icon: atribuindoEntregador
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1),
                label: Text(
                  atribuindoEntregador
                      ? 'Carregando entregadores...'
                      : 'Atribuir entregador',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

          if (podeEditar && nomeEntregador().isEmpty)
            const SizedBox(height: 12),

          if (podeEditar)
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final atualizado = await context.push<bool>(
                    '/empresa/entregas/editar',
                    extra: Map<String, dynamic>.from(entrega),
                  );

                  if (atualizado == true && context.mounted) {
                    context.pop(true);
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

          if (status == 'EM_ROTA') ...[
            _secaoAcompanhamento(),
            const SizedBox(height: 18),
          ],

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
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
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
