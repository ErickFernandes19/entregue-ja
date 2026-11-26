import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/entrega_service.dart';
import '../theme/app_colors.dart';

class FinalizarEntregaPage extends StatefulWidget {
  final int entregaId;
  final String cliente;
  final String endereco;

  const FinalizarEntregaPage({
    super.key,
    required this.entregaId,
    required this.cliente,
    required this.endereco,
  });

  @override
  State<FinalizarEntregaPage> createState() => _FinalizarEntregaPageState();
}

class _FinalizarEntregaPageState extends State<FinalizarEntregaPage> {
  final ImagePicker picker = ImagePicker();

  final TextEditingController justificativaController = TextEditingController();

  final TextEditingController observacaoController = TextEditingController();

  XFile? foto;
  Uint8List? fotoBytes;

  String tipoFinalizacao = 'ENTREGUE';
  String motivoSelecionado = 'DESTINATARIO_AUSENTE';

  bool enviando = false;
  bool buscandoLocalizacao = false;
  bool carregandoFoto = false;

  double? latitude;
  double? longitude;
  String? erroLocalizacao;

  final Map<String, String> motivos = {
    'DESTINATARIO_AUSENTE': 'Destinatário ausente',
    'LOCAL_FECHADO': 'Local fechado',
    'ENDERECO_NAO_LOCALIZADO': 'Endereço não localizado',
    'DESTINATARIO_RECUSOU': 'Destinatário recusou a entrega',
    'ACESSO_NAO_PERMITIDO': 'Acesso ao local não permitido',
    'OUTRO': 'Outro motivo',
  };

  @override
  void initState() {
    super.initState();
    obterLocalizacao();
  }

  void mostrarMensagem(String mensagem, {SnackBarAction? action}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem), action: action));
  }

  Future<void> tirarFoto() async {
    if (enviando || carregandoFoto) return;

    setState(() => carregandoFoto = true);

    try {
      final imagem = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (imagem == null || !mounted) return;

      final bytes = await imagem.readAsBytes();
      if (!mounted) return;

      if (bytes.isEmpty) {
        mostrarMensagem('A foto está vazia. Tire outra foto.');
        return;
      }

      if (bytes.length > 10 * 1024 * 1024) {
        mostrarMensagem('A imagem deve ter no máximo 10 MB. Tire outra foto.');
        return;
      }

      setState(() {
        foto = imagem;
        fotoBytes = bytes;
      });
    } on PlatformException catch (e) {
      debugPrint('Falha na câmera: ${e.code}');
      final mensagem = switch (e.code) {
        'camera_access_denied' || 'camera_access_denied_without_prompt' =>
          'Permita o acesso à câmera nas configurações do aplicativo ou navegador e tente novamente.',
        'camera_access_restricted' =>
          'O acesso à câmera está restrito neste dispositivo.',
        'no_available_camera' || 'camera_unavailable' =>
          'A câmera não está disponível neste dispositivo.',
        'already_active' => 'A câmera já está em uso. Tente novamente.',
        _ =>
          'Não foi possível capturar a foto. Verifique a câmera e tente novamente.',
      };
      mostrarMensagem(mensagem);
    } catch (e) {
      debugPrint('Falha ao obter foto: ${e.runtimeType}');
      mostrarMensagem('Não foi possível obter a foto. Tente novamente.');
    } finally {
      if (mounted) {
        setState(() => carregandoFoto = false);
      }
    }
  }

  Future<void> abrirConfiguracoesLocalizacao() async {
    try {
      if (!await Geolocator.openAppSettings()) {
        mostrarMensagem(
          'Abra as configurações do dispositivo e permita a localização.',
        );
      }
    } catch (_) {
      mostrarMensagem(
        'Abra as configurações do dispositivo e permita a localização.',
      );
    }
  }

  bool informarFalhaLocalizacao(
    String mensagem, {
    bool abrirConfiguracoes = false,
  }) {
    if (!mounted) return false;
    setState(() => erroLocalizacao = mensagem);
    mostrarMensagem(
      mensagem,
      action: abrirConfiguracoes && !kIsWeb
          ? SnackBarAction(
              label: 'Abrir',
              onPressed: abrirConfiguracoesLocalizacao,
            )
          : null,
    );
    return false;
  }

  Future<bool> obterLocalizacao() async {
    if (!mounted || buscandoLocalizacao) return false;

    setState(() {
      buscandoLocalizacao = true;
      latitude = null;
      longitude = null;
      erroLocalizacao = null;
    });

    try {
      final servicoAtivo = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return false;
      if (!servicoAtivo) {
        return informarFalhaLocalizacao(
          'Ative a localização do dispositivo para registrar a entrega.',
        );
      }

      var permissao = await Geolocator.checkPermission();
      if (!mounted) return false;
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }
      if (!mounted) return false;

      if (permissao == LocationPermission.denied) {
        return informarFalhaLocalizacao(
          'Permita o acesso à localização para registrar a entrega.',
        );
      }

      if (permissao == LocationPermission.deniedForever) {
        return informarFalhaLocalizacao(
          kIsWeb
              ? 'A localização foi bloqueada. Permita o acesso nas configurações do site no navegador.'
              : 'A localização foi bloqueada. Permita o acesso nas configurações do aplicativo.',
          abrirConfiguracoes: true,
        );
      }

      final posicao = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (!mounted) return false;

      if (!posicao.latitude.isFinite ||
          !posicao.longitude.isFinite ||
          posicao.latitude.abs() > 90 ||
          posicao.longitude.abs() > 180 ||
          (posicao.latitude == 0 && posicao.longitude == 0)) {
        return informarFalhaLocalizacao(
          'A localização recebida é inválida. Tente obter sua localização novamente.',
        );
      }

      setState(() {
        latitude = posicao.latitude;
        longitude = posicao.longitude;
      });

      return true;
    } on TimeoutException {
      return informarFalhaLocalizacao(
        'A localização demorou para responder. Vá para um local com melhor sinal e tente novamente.',
      );
    } on LocationServiceDisabledException {
      return informarFalhaLocalizacao(
        'Ative a localização do dispositivo e tente novamente.',
      );
    } on PermissionDeniedException {
      return informarFalhaLocalizacao(
        'Permita o acesso à localização nas configurações do aplicativo ou navegador e tente novamente.',
      );
    } catch (e) {
      debugPrint('Falha ao obter localização: ${e.runtimeType}');
      return informarFalhaLocalizacao(
        'Não foi possível obter sua localização. Tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => buscandoLocalizacao = false);
      }
    }
  }

  Future<void> finalizar() async {
    if (enviando || carregandoFoto || buscandoLocalizacao) return;

    final imagem = foto;
    final bytes = fotoBytes;
    final entregue = tipoFinalizacao == 'ENTREGUE';
    final motivo = motivoSelecionado;
    final justificativa = justificativaController.text.trim();
    final observacao = observacaoController.text.trim();

    if (imagem == null || bytes == null || bytes.isEmpty) {
      mostrarMensagem(
        entregue
            ? 'Tire uma foto para comprovar a entrega.'
            : 'Tire uma foto para comprovar a tentativa.',
      );
      return;
    }

    if (!entregue && justificativa.isEmpty) {
      mostrarMensagem('Escreva uma justificativa para a não entrega.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => enviando = true);

    try {
      final localizacaoObtida = await obterLocalizacao();
      if (!mounted || !localizacaoObtida) return;

      final lat = latitude;
      final lng = longitude;
      if (lat == null || lng == null) {
        informarFalhaLocalizacao(
          'Não foi possível obter sua localização. Tente novamente.',
        );
        return;
      }

      final resultado = entregue
          ? await EntregaService.concluirEntrega(
              idEntrega: widget.entregaId.toString(),
              fotoBytes: bytes,
              nomeArquivo: imagem.name,
              latitude: lat,
              longitude: lng,
              observacao: observacao,
              lancarErro: true,
            )
          : await EntregaService.registrarNaoEntrega(
              idEntrega: widget.entregaId.toString(),
              fotoBytes: bytes,
              nomeArquivo: imagem.name,
              motivo: motivo,
              justificativa: justificativa,
              latitude: lat,
              longitude: lng,
              lancarErro: true,
            );

      if (!mounted) return;

      if (resultado == null) {
        mostrarMensagem(
          'Não foi possível confirmar o registro. Confira a situação da entrega antes de tentar novamente.',
        );
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              entregue
                  ? 'Entrega concluída com sucesso!'
                  : 'Tentativa de entrega registrada com sucesso!',
            ),
            backgroundColor: entregue ? AppColors.success : AppColors.warning,
          ),
        );

      context.pop(true);
    } catch (e) {
      debugPrint('Falha ao finalizar entrega: ${e.runtimeType}');
      final mensagem = ApiService.mensagemErro(
        e,
        mensagemPadrao: entregue
            ? 'Não foi possível concluir a entrega.'
            : 'Não foi possível registrar a tentativa de entrega.',
      );
      final status = e is ApiException ? e.statusCode : null;
      mostrarMensagem(
        (status == null || status == 408 || status >= 500) &&
                !mensagem.contains('Verifique o resultado da operação')
            ? '$mensagem Confira a situação da entrega antes de tentar novamente.'
            : mensagem,
      );
    } finally {
      if (mounted) {
        setState(() => enviando = false);
      }
    }
  }

  Widget opcaoFinalizacao({
    required String valor,
    required IconData icon,
    required String titulo,
    required String descricao,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final selecionado = tipoFinalizacao == valor;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enviando
          ? null
          : () {
              setState(() {
                tipoFinalizacao = valor;
              });
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selecionado ? color.withValues(alpha: 0.12) : theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selecionado ? color : theme.colorScheme.outlineVariant,
            width: selecionado ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    descricao,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Radio<String>(value: valor, activeColor: color, enabled: !enviando),
          ],
        ),
      ),
    );
  }

  Widget areaFoto() {
    final theme = Theme.of(context);

    if (carregandoFoto) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (fotoBytes != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(
              fotoBytes!,
              height: 230,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: enviando ? null : tirarFoto,
            icon: const Icon(Icons.refresh),
            label: const Text('Alterar foto'),
          ),
        ],
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: enviando ? null : tirarFoto,
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo, size: 48, color: AppColors.primary),
            const SizedBox(height: 10),
            const Text(
              'Adicionar foto',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Use a câmera para fotografar o local da entrega.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget statusLocalizacao() {
    final theme = Theme.of(context);

    final possuiLocalizacao = latitude != null && longitude != null;

    final cor = possuiLocalizacao ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          if (buscandoLocalizacao)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              possuiLocalizacao ? Icons.location_on : Icons.location_off,
              color: cor,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              buscandoLocalizacao
                  ? 'Obtendo sua localização...'
                  : possuiLocalizacao
                  ? 'Localização registrada'
                  : (erroLocalizacao ?? 'Localização ainda não disponível'),
              style: TextStyle(fontWeight: FontWeight.w600, color: cor),
            ),
          ),
          if (!possuiLocalizacao && !buscandoLocalizacao)
            IconButton(
              tooltip: 'Tentar novamente',
              onPressed: enviando ? null : obterLocalizacao,
              icon: Icon(Icons.refresh, color: theme.colorScheme.onSurface),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    justificativaController.dispose();
    observacaoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final naoEntregue = tipoFinalizacao == 'NAO_ENTREGUE';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back),
          onPressed: enviando
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop(false);
                  } else {
                    context.go('/entregador/entregas');
                  }
                },
        ),
        title: const Text('Finalizar Entrega'),
        centerTitle: true,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Entrega #${widget.entregaId}',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.cliente,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 19,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.endereco,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            statusLocalizacao(),
            const SizedBox(height: 24),

            Text(
              'Resultado da entrega',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 12),

            RadioGroup<String>(
              groupValue: tipoFinalizacao,
              onChanged: (valor) {
                if (enviando || valor == null) return;
                setState(() => tipoFinalizacao = valor);
              },
              child: Column(
                children: [
                  opcaoFinalizacao(
                    valor: 'ENTREGUE',
                    icon: Icons.check_circle,
                    titulo: 'Entrega realizada',
                    descricao: 'O pedido foi entregue ao destinatário.',
                    color: AppColors.success,
                  ),

                  opcaoFinalizacao(
                    valor: 'NAO_ENTREGUE',
                    icon: Icons.report_problem,
                    titulo: 'Não foi possível entregar',
                    descricao: 'Registre a tentativa e informe o motivo.',
                    color: AppColors.error,
                  ),
                ],
              ),
            ),

            if (naoEntregue) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: motivoSelecionado,
                dropdownColor: theme.cardColor,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Motivo da não entrega',
                  prefixIcon: Icon(Icons.help_outline),
                ),
                items: motivos.entries.map((motivo) {
                  return DropdownMenuItem<String>(
                    value: motivo.key,
                    child: Text(motivo.value),
                  );
                }).toList(),
                onChanged: enviando
                    ? null
                    : (valor) {
                        if (valor == null) return;

                        setState(() {
                          motivoSelecionado = valor;
                        });
                      },
              ),

              const SizedBox(height: 14),

              TextField(
                controller: justificativaController,
                enabled: !enviando,
                maxLines: 4,
                maxLength: 500,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Justificativa',
                  hintText:
                      'Ex: Toquei o interfone várias vezes e ninguém respondeu.',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 65),
                    child: Icon(Icons.description),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),

              TextField(
                controller: observacaoController,
                enabled: !enviando,
                maxLines: 3,
                maxLength: 300,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  hintText: 'Ex: Entregue ao próprio destinatário.',
                  alignLabelWithHint: true,
                ),
              ),
            ],

            const SizedBox(height: 18),

            Text(
              'Comprovante fotográfico',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              naoEntregue
                  ? 'Fotografe o local para comprovar que a tentativa foi realizada.'
                  : 'Fotografe o pedido no local da entrega para registrar a conclusão.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),

            const SizedBox(height: 14),
            areaFoto(),
            const SizedBox(height: 30),

            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: enviando || carregandoFoto || buscandoLocalizacao
                    ? null
                    : finalizar,
                icon: enviando
                    ? const SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        naoEntregue ? Icons.report_problem : Icons.check_circle,
                      ),
                label: Text(
                  enviando
                      ? (buscandoLocalizacao
                            ? 'Obtendo localização...'
                            : 'Enviando...')
                      : naoEntregue
                      ? 'Registrar Tentativa'
                      : 'Confirmar Entrega',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: naoEntregue
                      ? AppColors.error
                      : AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
