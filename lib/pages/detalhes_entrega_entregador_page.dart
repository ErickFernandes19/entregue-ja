import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/entrega_service.dart';
import '../theme/app_colors.dart';

class DetalhesEntregaEntregadorPage extends StatefulWidget {
  final Map<String, dynamic> entrega;

  const DetalhesEntregaEntregadorPage({super.key, required this.entrega});

  @override
  State<DetalhesEntregaEntregadorPage> createState() =>
      _DetalhesEntregaEntregadorPageState();
}

class _DetalhesEntregaEntregadorPageState
    extends State<DetalhesEntregaEntregadorPage> {
  late Map<String, dynamic> dados;
  Uint8List? fotoAtual;
  bool carregandoFoto = false;
  bool carregandoHistorico = true;
  bool erroHistorico = false;
  bool preparandoTentativa = false;
  List<Map<String, dynamic>> tentativas = [];
  final Map<String, Uint8List> fotosTentativas = {};
  final Set<String> carregandoFotos = {};

  String get id => (dados['id'] ?? '').toString();
  String get status =>
      (dados['status'] ?? (dados['entregue'] == true ? 'ENTREGUE' : 'PENDENTE'))
          .toString();

  @override
  void initState() {
    super.initState();
    dados = Map<String, dynamic>.from(widget.entrega);
    atualizarDados();
  }

  Future<void> atualizarDados() async {
    if (id.isEmpty) return;
    final entregaAtual = await EntregaService.buscarEntrega(id);
    if (!mounted) return;
    if (entregaAtual != null) {
      setState(() => dados = entregaAtual);
    }
    await Future.wait([carregarHistorico(), carregarFotoAtual()]);
  }

  Future<void> carregarFotoAtual() async {
    final referencia = (dados['fotoComprovante'] ?? '').toString();
    if (referencia.isEmpty) {
      if (mounted) setState(() => fotoAtual = null);
      return;
    }
    setState(() => carregandoFoto = true);
    final bytes = await EntregaService.buscarBytesComprovante(
      idEntrega: id,
      referencia: referencia,
    );
    if (!mounted) return;
    setState(() {
      fotoAtual = bytes;
      carregandoFoto = false;
    });
  }

  Future<void> carregarHistorico() async {
    if (id.isEmpty) return;
    setState(() {
      carregandoHistorico = true;
      erroHistorico = false;
    });
    try {
      final headers = await AuthService.headersAutenticados();
      final resposta = await http.get(
        Uri.parse(
          '${ApiConfig.entregas}/${Uri.encodeComponent(id)}/tentativas',
        ),
        headers: headers,
      );
      if (resposta.statusCode != 200) {
        throw Exception('HTTP ${resposta.statusCode}');
      }
      final json = jsonDecode(resposta.body);
      final lista = json is Map ? json['tentativas'] : null;
      if (!mounted) return;
      setState(() {
        tentativas = lista is List
            ? lista
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : [];
      });
    } catch (e) {
      debugPrint('Erro ao buscar histórico: $e');
      if (mounted) setState(() => erroHistorico = true);
    } finally {
      if (mounted) setState(() => carregandoHistorico = false);
    }
  }

  Future<void> abrirFotoTentativa(Map<String, dynamic> tentativa) async {
    final tentativaId = (tentativa['id'] ?? '').toString();
    if (tentativaId.isEmpty || carregandoFotos.contains(tentativaId)) return;
    var bytes = fotosTentativas[tentativaId];
    if (bytes == null) {
      setState(() => carregandoFotos.add(tentativaId));
      try {
        final headers = await AuthService.headersAutenticados();
        final resposta = await http.get(
          Uri.parse(
            '${ApiConfig.entregas}/${Uri.encodeComponent(id)}/tentativas/${Uri.encodeComponent(tentativaId)}/comprovante',
          ),
          headers: headers,
        );
        if (resposta.statusCode == 200) {
          bytes = resposta.bodyBytes;
          fotosTentativas[tentativaId] = bytes;
        }
      } catch (e) {
        debugPrint('Erro ao buscar foto da tentativa: $e');
      } finally {
        if (mounted) setState(() => carregandoFotos.remove(tentativaId));
      }
    }
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      mensagem('Não foi possível carregar a fotografia.');
      return;
    }
    mostrarImagem(bytes);
  }

  void mostrarImagem(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
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
                      'Comprovante fotográfico',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
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
      ),
    );
  }

  void mensagem(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> tentarNovamente() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova tentativa'),
        content: const Text(
          'Deseja disponibilizar esta entrega para uma nova tentativa? O histórico anterior será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => preparandoTentativa = true);
    try {
      final headers = await AuthService.headersAutenticados();
      final resposta = await http.put(
        Uri.parse(
          '${ApiConfig.entregas}/${Uri.encodeComponent(id)}/nova-tentativa',
        ),
        headers: headers,
      );
      if (!mounted) return;
      if (resposta.statusCode == 200) {
        mensagem('Entrega disponível para nova tentativa.');
        await atualizarDados();
      } else {
        mensagem(
          'Não foi possível preparar a nova tentativa (${resposta.statusCode}).',
        );
      }
    } catch (e) {
      if (mounted) mensagem('Erro de conexão ao preparar a nova tentativa.');
    } finally {
      if (mounted) setState(() => preparandoTentativa = false);
    }
  }

  Future<void> abrirLocalizacao(dynamic latitude, dynamic longitude) async {
    final lat = double.tryParse((latitude ?? '').toString());
    final lng = double.tryParse((longitude ?? '').toString());
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      mensagem('Não foi possível abrir a localização.');
    }
  }

  String textoStatus(String valor) {
    switch (valor) {
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

  Color corStatus(String valor) {
    switch (valor) {
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

  String motivoTexto(String valor) {
    const motivos = {
      'DESTINATARIO_AUSENTE': 'Destinatário ausente',
      'LOCAL_FECHADO': 'Local fechado',
      'ENDERECO_NAO_LOCALIZADO': 'Endereço não localizado',
      'DESTINATARIO_RECUSOU': 'Destinatário recusou a entrega',
      'ACESSO_NAO_PERMITIDO': 'Acesso ao local não permitido',
      'OUTRO': 'Outro motivo',
    };
    return motivos[valor] ?? valor;
  }

  String dataTexto(dynamic valor) {
    final data = DateTime.tryParse((valor ?? '').toString());
    if (data == null) return 'Data não informada';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}/${data.year} às ${dois(data.hour)}:${dois(data.minute)}';
  }

  Widget informacao(IconData icone, String titulo, String valor) {
    final cores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
            child: Icon(icone, color: AppColors.primary, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cores.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget painel({
    required String titulo,
    required IconData icone,
    required Widget conteudo,
  }) {
    final tema = Theme.of(context);
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
              Icon(icone, color: AppColors.primary, size: 25),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          conteudo,
        ],
      ),
    );
  }

  Widget historico() {
    if (carregandoHistorico) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (erroHistorico) {
      return Column(
        children: [
          const Text('Não foi possível carregar o histórico.'),
          TextButton.icon(
            onPressed: carregarHistorico,
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar'),
          ),
        ],
      );
    }
    if (tentativas.isEmpty)
      return const Text('Nenhuma tentativa registrada no histórico.');
    return Column(
      children: tentativas.map((t) {
        final resultado = (t['resultado'] ?? '').toString();
        final motivo = (t['motivo'] ?? '').toString();
        final justificativa = (t['justificativa'] ?? '').toString();
        final possuiFoto = t['possuiFoto'] == true;
        final tentativaId = (t['id'] ?? '').toString();
        final lat = t['latitude'];
        final lng = t['longitude'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tentativa ${t['numeroTentativa'] ?? ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      textoStatus(resultado),
                      style: TextStyle(
                        color: corStatus(resultado),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(dataTexto(t['dataTentativa'])),
                if (motivo.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Motivo: ${motivoTexto(motivo)}'),
                ],
                if (justificativa.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Justificativa: $justificativa'),
                ],
                if (possuiFoto || (lat != null && lng != null)) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (possuiFoto)
                        OutlinedButton.icon(
                          onPressed: carregandoFotos.contains(tentativaId)
                              ? null
                              : () => abrirFotoTentativa(t),
                          icon: carregandoFotos.contains(tentativaId)
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.photo_outlined),
                          label: const Text('Ver foto'),
                        ),
                      if (lat != null && lng != null)
                        OutlinedButton.icon(
                          onPressed: () => abrirLocalizacao(lat, lng),
                          icon: const Icon(Icons.location_on_outlined),
                          label: const Text('Ver GPS'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cliente = (dados['cliente'] ?? '').toString();
    final endereco = (dados['endereco'] ?? '').toString();
    final complemento = (dados['complemento'] ?? '').toString();
    final observacao = (dados['observacao'] ?? '').toString();
    final valor = double.tryParse((dados['valor'] ?? 0).toString()) ?? 0;
    final responsavel = dados['entregador'];
    final nomeEntregador = responsavel is Map
        ? (responsavel['nome'] ?? responsavel['email'] ?? '').toString()
        : '';
    final referencia = (dados['fotoComprovante'] ?? '').toString();
    final motivo = (dados['motivoNaoEntrega'] ?? '').toString();
    final justificativa = (dados['justificativa'] ?? '').toString();
    final finalizada = status == 'ENTREGUE' || status == 'NAO_ENTREGUE';

    return Scaffold(
      appBar: AppBar(
        title: Text('Entrega #$id'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: atualizarDados,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
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
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                informacao(
                  Icons.location_on_outlined,
                  'Endereço',
                  endereco.isEmpty ? 'Não informado' : endereco,
                ),
                if (complemento.isNotEmpty)
                  informacao(Icons.apartment, 'Complemento', complemento),
                informacao(
                  Icons.attach_money,
                  'Valor',
                  'R\$ ${valor.toStringAsFixed(2)}',
                ),
                if (observacao.isNotEmpty)
                  informacao(Icons.notes, 'Observação', observacao),
                if (nomeEntregador.isNotEmpty)
                  informacao(
                    Icons.delivery_dining,
                    'Entregador responsável',
                    nomeEntregador,
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: corStatus(status).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    textoStatus(status),
                    style: TextStyle(
                      color: corStatus(status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (status == 'NAO_ENTREGUE') ...[
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: preparandoTentativa ? null : tentarNovamente,
                icon: preparandoTentativa
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (status == 'PENDENTE' || status == 'EM_ROTA') ...[
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final resultado = await context.push<bool>(
                    '/entregador/entregas/finalizar',
                    extra: {
                      'entregaId': int.tryParse(id) ?? 0,
                      'cliente': cliente,
                      'endereco': endereco,
                    },
                  );
                  if (!mounted) return;
                  if (resultado == true) {
                    await atualizarDados();
                  }
                },
                icon: const Icon(Icons.task_alt),
                label: const Text('Finalizar entrega'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (status == 'NAO_ENTREGUE') ...[
            painel(
              titulo: 'Detalhes da não entrega',
              icone: Icons.report_problem_outlined,
              conteudo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Motivo: ${motivo.isEmpty ? 'Não informado' : motivoTexto(motivo)}',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Justificativa: ${justificativa.isEmpty ? 'Não informada' : justificativa}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (finalizada && referencia.isNotEmpty) ...[
            painel(
              titulo: 'Comprovante fotográfico',
              icone: Icons.photo_camera,
              conteudo: Column(
                children: [
                  if (carregandoFoto)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    )
                  else if (fotoAtual != null && fotoAtual!.isNotEmpty)
                    InkWell(
                      onTap: () => mostrarImagem(fotoAtual!),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          fotoAtual!,
                          height: 230,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    const Text('Comprovante indisponível.'),
                  if (fotoAtual != null)
                    TextButton.icon(
                      onPressed: () => mostrarImagem(fotoAtual!),
                      icon: const Icon(Icons.zoom_in),
                      label: const Text('Ampliar comprovante'),
                    ),
                  if (dados['latitudeComprovante'] != null &&
                      dados['longitudeComprovante'] != null)
                    OutlinedButton.icon(
                      onPressed: () => abrirLocalizacao(
                        dados['latitudeComprovante'],
                        dados['longitudeComprovante'],
                      ),
                      icon: const Icon(Icons.location_on_outlined),
                      label: const Text('Localização do comprovante'),
                    ),
                  if (dados['dataFinalizacao'] != null)
                    Text(dataTexto(dados['dataFinalizacao'])),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          painel(
            titulo: 'Histórico de tentativas (${tentativas.length})',
            icone: Icons.history,
            conteudo: historico(),
          ),
          const SizedBox(height: 18),
          painel(
            titulo: 'QR Code da Entrega',
            icone: Icons.qr_code,
            conteudo: Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: QrImageView(
                      data: id,
                      size: 230,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'ID: $id',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
