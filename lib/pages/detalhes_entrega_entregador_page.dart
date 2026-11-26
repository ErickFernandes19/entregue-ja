import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
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
  bool carregandoHistorico = false;
  String? erroHistorico;
  String? erroDados;
  String? erroFoto;
  String? referenciaFotoAtual;
  bool acessoIndisponivel = false;
  bool historicoCarregado = false;
  static const _tempoLimite = Duration(seconds: 20);
  bool preparandoTentativa = false;
  bool salvandoEdicao = false;
  bool atualizandoDados = false;
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

  Future<Map<String, String>> _headersAutenticados() async {
    final headers = await AuthService.headersAutenticados();
    if ((headers['Authorization'] ?? '').trim().isEmpty) {
      throw const ApiException(
        'Sua sessão expirou. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
    return headers;
  }

  bool _acessoIndisponivel(Object erro) =>
      erro is ApiException && [401, 403, 404].contains(erro.statusCode);

  String _mensagemErro(Object erro, String padrao) =>
      ApiService.mensagemErro(erro, mensagemPadrao: padrao);

  void _validarResposta(http.Response resposta) {
    if (resposta.statusCode != 200) {
      throw ApiService.erroHttp(
        resposta.statusCode,
        utf8.decode(resposta.bodyBytes, allowMalformed: true),
      );
    }
  }

  Future<void> atualizarDados() async {
    if (!mounted ||
        atualizandoDados ||
        carregandoHistorico ||
        carregandoFoto ||
        carregandoFotos.isNotEmpty) {
      return;
    }
    if (id.trim().isEmpty) {
      setState(() {
        erroDados = 'Não foi possível identificar a entrega.';
        acessoIndisponivel = true;
      });
      return;
    }

    setState(() => atualizandoDados = true);
    try {
      final entregaAtual = await EntregaService.buscarEntrega(
        id,
        lancarErro: true,
      );
      if (!mounted) {
        return;
      }
      if (entregaAtual == null || entregaAtual['id']?.toString() != id) {
        throw const FormatException('Resposta inválida da entrega.');
      }
      setState(() {
        dados = entregaAtual;
        erroDados = null;
        acessoIndisponivel = false;
        fotosTentativas.clear();
      });
      await Future.wait([carregarHistorico(), carregarFotoAtual()]);
    } catch (e) {
      debugPrint('Erro ao atualizar detalhes: ${e.runtimeType}');
      if (!mounted) {
        return;
      }
      setState(() {
        erroDados = _mensagemErro(
          e,
          'Não foi possível atualizar os dados da entrega.',
        );
        if (_acessoIndisponivel(e)) {
          acessoIndisponivel = true;
          tentativas = [];
          historicoCarregado = false;
          fotosTentativas.clear();
          fotoAtual = null;
          referenciaFotoAtual = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() => atualizandoDados = false);
      }
    }
  }

  Future<void> carregarFotoAtual() async {
    if (!mounted || carregandoFoto || acessoIndisponivel) {
      return;
    }
    final referencia = (dados['fotoComprovante'] ?? '').toString().trim();
    if (referencia.isEmpty) {
      setState(() {
        fotoAtual = null;
        referenciaFotoAtual = null;
        erroFoto = null;
      });
      return;
    }
    setState(() {
      carregandoFoto = true;
      erroFoto = null;
      if (referenciaFotoAtual != referencia) {
        fotoAtual = null;
      }
    });
    try {
      final bytes = await EntregaService.buscarBytesComprovante(
        idEntrega: id,
        referencia: referencia,
        lancarErro: true,
      );
      if (!mounted) {
        return;
      }
      if (bytes == null || bytes.isEmpty) {
        throw const ApiException('O comprovante está indisponível.');
      }
      setState(() {
        fotoAtual = bytes;
        referenciaFotoAtual = referencia;
      });
    } catch (e) {
      debugPrint('Erro ao carregar comprovante: ${e.runtimeType}');
      if (!mounted) {
        return;
      }
      setState(() {
        erroFoto = _mensagemErro(e, 'Não foi possível carregar o comprovante.');
        if (_acessoIndisponivel(e)) {
          fotoAtual = null;
          referenciaFotoAtual = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() => carregandoFoto = false);
      }
    }
  }

  Future<void> carregarHistorico() async {
    if (!mounted ||
        carregandoHistorico ||
        acessoIndisponivel ||
        carregandoFotos.isNotEmpty) {
      return;
    }
    if (id.trim().isEmpty) {
      setState(() => erroHistorico = 'Não foi possível identificar a entrega.');
      return;
    }
    setState(() {
      carregandoHistorico = true;
      erroHistorico = null;
    });
    try {
      final headers = await _headersAutenticados();
      final resposta = await http
          .get(
            Uri.parse(
              '${ApiConfig.entregas}/${Uri.encodeComponent(id)}/tentativas',
            ),
            headers: headers,
          )
          .timeout(_tempoLimite);
      _validarResposta(resposta);
      final json = jsonDecode(utf8.decode(resposta.bodyBytes));
      final lista = json is Map ? json['tentativas'] : null;
      if (lista is! List ||
          lista.any((item) => item is! Map<String, dynamic>)) {
        throw const FormatException('Resposta inválida do histórico.');
      }
      final novasTentativas = lista.cast<Map<String, dynamic>>().toList();
      if (!mounted) {
        return;
      }
      setState(() {
        tentativas = novasTentativas;
        historicoCarregado = true;
      });
    } catch (e) {
      debugPrint('Erro ao buscar histórico: ${e.runtimeType}');
      if (!mounted) {
        return;
      }
      setState(() {
        erroHistorico = _mensagemErro(
          e,
          'Não foi possível carregar o histórico.',
        );
        if (_acessoIndisponivel(e)) {
          tentativas = [];
          fotosTentativas.clear();
          historicoCarregado = false;
        }
      });
    } finally {
      if (mounted) {
        setState(() => carregandoHistorico = false);
      }
    }
  }

  Future<void> abrirFotoTentativa(Map<String, dynamic> tentativa) async {
    if (!mounted ||
        atualizandoDados ||
        carregandoHistorico ||
        acessoIndisponivel ||
        preparandoTentativa ||
        salvandoEdicao) {
      return;
    }
    final tentativaId = (tentativa['id'] ?? '').toString();
    if (tentativaId.isEmpty) {
      mensagem('Não foi possível identificar a tentativa.');
      return;
    }
    if (carregandoFotos.contains(tentativaId)) {
      return;
    }
    var bytes = fotosTentativas[tentativaId];
    if (bytes == null) {
      setState(() => carregandoFotos.add(tentativaId));
      try {
        final headers = await _headersAutenticados();
        final resposta = await http
            .get(
              Uri.parse(
                '${ApiConfig.entregas}/${Uri.encodeComponent(id)}/tentativas/${Uri.encodeComponent(tentativaId)}/comprovante',
              ),
              headers: headers,
            )
            .timeout(_tempoLimite);
        _validarResposta(resposta);
        if (resposta.bodyBytes.isEmpty) {
          throw const ApiException('A fotografia está indisponível.');
        }
        if (!mounted) {
          return;
        }
        bytes = resposta.bodyBytes;
        fotosTentativas[tentativaId] = bytes;
      } catch (e) {
        debugPrint('Erro ao buscar foto da tentativa: ${e.runtimeType}');
        if (mounted) {
          mensagem(_mensagemErro(e, 'Não foi possível carregar a fotografia.'));
        }
        return;
      } finally {
        if (mounted) {
          setState(() => carregandoFotos.remove(tentativaId));
        }
      }
    }
    if (!mounted || acessoIndisponivel) {
      return;
    }
    if (bytes.isEmpty) {
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
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Não foi possível visualizar esta fotografia.'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void mensagem(String texto) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  bool get _acoesBloqueadas =>
      atualizandoDados ||
      erroDados != null ||
      acessoIndisponivel ||
      preparandoTentativa ||
      salvandoEdicao ||
      carregandoHistorico ||
      carregandoFoto ||
      carregandoFotos.isNotEmpty;

  Future<void> tentarNovamente() async {
    if (_acoesBloqueadas || status != 'NAO_ENTREGUE') {
      return;
    }
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
    if (confirmar != true || !mounted || _acoesBloqueadas) {
      return;
    }
    setState(() => preparandoTentativa = true);
    try {
      final headers = await _headersAutenticados();
      final resposta = await http
          .put(
            Uri.parse(
              '${ApiConfig.entregas}/${Uri.encodeComponent(id)}/nova-tentativa',
            ),
            headers: headers,
          )
          .timeout(_tempoLimite);
      _validarResposta(resposta);
      if (!mounted) {
        return;
      }
      mensagem('Entrega disponível para nova tentativa.');
      await atualizarDados();
    } catch (e) {
      if (mounted) {
        mensagem(
          _mensagemErro(
            e,
            'Não foi possível preparar a nova tentativa. Atualize os dados antes de tentar novamente.',
          ),
        );
      }
      if (mounted) {
        await atualizarDados();
      }
    } finally {
      if (mounted) {
        setState(() => preparandoTentativa = false);
      }
    }
  }

  Future<void> editarEntrega() async {
    if (id.isEmpty ||
        dados['empresa'] != null ||
        !['PENDENTE', 'EM_ROTA'].contains(status.toUpperCase()) ||
        _acoesBloqueadas) {
      return;
    }

    final clienteController = TextEditingController(
      text: (dados['cliente'] ?? '').toString(),
    );
    final enderecoController = TextEditingController(
      text: (dados['endereco'] ?? '').toString(),
    );
    final complementoController = TextEditingController(
      text: (dados['complemento'] ?? '').toString(),
    );
    final valorController = TextEditingController(
      text: (dados['valor'] ?? 0).toString().replaceAll('.', ','),
    );
    final observacaoController = TextEditingController(
      text: (dados['observacao'] ?? '').toString(),
    );
    final chaveFormulario = GlobalKey<FormState>();
    var enviando = false;
    String? erroEdicao;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, atualizarDialogo) => PopScope(
            canPop: !enviando,
            child: AlertDialog(
              title: const Text('Editar entrega'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Form(
                    key: chaveFormulario,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: clienteController,
                          enabled: !enviando,
                          decoration: const InputDecoration(
                            labelText: 'Cliente',
                          ),
                          validator: (valor) =>
                              valor == null || valor.trim().isEmpty
                              ? 'Informe o cliente'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: enderecoController,
                          enabled: !enviando,
                          decoration: const InputDecoration(
                            labelText: 'Endereço',
                          ),
                          validator: (valor) =>
                              valor == null || valor.trim().isEmpty
                              ? 'Informe o endereço'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: complementoController,
                          enabled: !enviando,
                          decoration: const InputDecoration(
                            labelText: 'Complemento',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: valorController,
                          enabled: !enviando,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor (R\$)',
                          ),
                          validator: (valor) {
                            final numero = double.tryParse(
                              (valor ?? '').trim().replaceAll(',', '.'),
                            );
                            return numero == null ||
                                    !numero.isFinite ||
                                    numero < 0
                                ? 'Informe um valor válido'
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: observacaoController,
                          enabled: !enviando,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Observação',
                          ),
                        ),
                        if (erroEdicao != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            erroEdicao!,
                            style: TextStyle(
                              color: Theme.of(dialogContext).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: enviando
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: enviando
                      ? null
                      : () async {
                          if (!(chaveFormulario.currentState?.validate() ??
                              false)) {
                            return;
                          }
                          if (enviando || _acoesBloqueadas) {
                            return;
                          }
                          atualizarDialogo(() {
                            enviando = true;
                            erroEdicao = null;
                          });
                          setState(() => salvandoEdicao = true);
                          try {
                            final headers = await _headersAutenticados();
                            final resposta = await http
                                .put(
                                  Uri.parse(
                                    '${ApiConfig.entregas}/${Uri.encodeComponent(id)}',
                                  ),
                                  headers: {
                                    ...headers,
                                    'Content-Type': 'application/json',
                                  },
                                  body: jsonEncode({
                                    'cliente': clienteController.text.trim(),
                                    'endereco': enderecoController.text.trim(),
                                    'complemento': complementoController.text
                                        .trim(),
                                    'valor': double.parse(
                                      valorController.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    ),
                                    'observacao': observacaoController.text
                                        .trim(),
                                  }),
                                )
                                .timeout(_tempoLimite);
                            _validarResposta(resposta);
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.pop(dialogContext);
                            await atualizarDados();
                            if (mounted) {
                              mensagem('Entrega atualizada com sucesso.');
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              atualizarDialogo(() {
                                erroEdicao = _mensagemErro(
                                  e,
                                  'Não foi possível editar a entrega.',
                                );
                              });
                            }
                          } finally {
                            if (mounted) {
                              setState(() => salvandoEdicao = false);
                            }
                            if (dialogContext.mounted) {
                              atualizarDialogo(() => enviando = false);
                            }
                          }
                        },
                  child: enviando
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      clienteController.dispose();
      enderecoController.dispose();
      complementoController.dispose();
      valorController.dispose();
      observacaoController.dispose();
    }
  }

  Future<void> abrirLocalizacao(dynamic latitude, dynamic longitude) async {
    final lat = double.tryParse((latitude ?? '').toString());
    final lng = double.tryParse((longitude ?? '').toString());
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      mensagem('A localização registrada é inválida ou está indisponível.');
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        mensagem('Não foi possível abrir a localização.');
      }
    } catch (e) {
      if (mounted) {
        mensagem('Não foi possível abrir a localização.');
      }
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
    if (data == null) {
      return 'Data não informada';
    }
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
    if (carregandoHistorico && !historicoCarregado) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (erroHistorico != null && !historicoCarregado) {
      return _avisoErro(erroHistorico!, carregarHistorico);
    }
    if (!historicoCarregado) {
      return const Text('Histórico ainda não carregado.');
    }
    if (tentativas.isEmpty && erroHistorico == null) {
      return const Text('Nenhuma tentativa registrada no histórico.');
    }
    return Column(
      children: [
        if (carregandoHistorico) const LinearProgressIndicator(),
        if (erroHistorico != null)
          _avisoErro(
            '${erroHistorico!} O histórico exibido pode estar desatualizado.',
            carregarHistorico,
          ),
        ...tentativas.map((t) {
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
                            onPressed:
                                (atualizandoDados ||
                                    carregandoHistorico ||
                                    carregandoFotos.contains(tentativaId))
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
        }),
      ],
    );
  }

  bool get _atualizacaoBloqueada =>
      atualizandoDados ||
      carregandoHistorico ||
      carregandoFoto ||
      carregandoFotos.isNotEmpty ||
      preparandoTentativa ||
      salvandoEdicao;

  Widget _avisoErro(String texto, Future<void> Function() tentar) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton.icon(
            onPressed: _atualizacaoBloqueada ? null : tentar,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
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
        leading: IconButton(
          tooltip: 'Voltar às entregas',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop(true);
            } else {
              context.go('/entregador/entregas');
            }
          },
        ),
        title: Text('Entrega #$id'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _atualizacaoBloqueada ? null : atualizarDados,
            tooltip: 'Atualizar',
            icon: atualizandoDados
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: acessoIndisponivel
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _avisoErro(
                  erroDados ?? 'Não foi possível acessar a entrega.',
                  atualizarDados,
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (erroDados != null)
                  _avisoErro(
                    '${erroDados!} Os dados exibidos podem estar desatualizados.',
                    atualizarDados,
                  ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: tema.cardColor,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: tema.colorScheme.outlineVariant.withValues(
                        alpha: 0.35,
                      ),
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
                              cliente.isEmpty
                                  ? 'Cliente não informado'
                                  : cliente,
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
                if (dados['empresa'] == null &&
                    (status == 'PENDENTE' || status == 'EM_ROTA')) ...[
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _acoesBloqueadas ? null : editarEntrega,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar entrega'),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (status == 'NAO_ENTREGUE') ...[
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _acoesBloqueadas ? null : tentarNovamente,
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
                      onPressed: _acoesBloqueadas
                          ? null
                          : () async {
                              final resultado = await context.push<bool>(
                                '/entregador/entregas/finalizar',
                                extra: {
                                  'entregaId': int.tryParse(id) ?? 0,
                                  'cliente': cliente,
                                  'endereco': endereco,
                                },
                              );
                              if (!mounted) {
                                return;
                              }
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
                                errorBuilder: (_, _, _) => _avisoErro(
                                  'Não foi possível visualizar o comprovante.',
                                  carregarFotoAtual,
                                ),
                              ),
                            ),
                          )
                        else if (erroFoto == null)
                          const Text('Comprovante indisponível.'),
                        if (erroFoto != null)
                          _avisoErro(erroFoto!, carregarFotoAtual),
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
                  titulo: historicoCarregado
                      ? 'Histórico de tentativas (${tentativas.length})'
                      : 'Histórico de tentativas',
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
