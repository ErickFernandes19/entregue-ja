import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
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

  String tipoFinalizacao = 'ENTREGUE';

  String motivoSelecionado = 'DESTINATARIO_AUSENTE';

  bool enviando = false;
  bool buscandoLocalizacao = false;

  double? latitude;
  double? longitude;

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

  Future<void> tirarFoto() async {
    try {
      final imagem = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (imagem == null) return;

      if (!mounted) return;

      setState(() {
        foto = imagem;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir a câmera: $e')),
      );
    }
  }

  Future<bool> obterLocalizacao() async {
    if (!mounted) return false;

    setState(() {
      buscandoLocalizacao = true;
    });

    try {
      final servicoAtivo = await Geolocator.isLocationServiceEnabled();

      if (!servicoAtivo) {
        if (!mounted) return false;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ative a localização do celular para registrar a entrega.',
            ),
          ),
        );

        return false;
      }

      LocationPermission permissao = await Geolocator.checkPermission();

      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }

      if (permissao == LocationPermission.denied) {
        if (!mounted) return false;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A permissão de localização é necessária.'),
          ),
        );

        return false;
      }

      if (permissao == LocationPermission.deniedForever) {
        if (!mounted) return false;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'A permissão de localização foi bloqueada. '
              'Ative-a nas configurações do aplicativo.',
            ),
            action: SnackBarAction(
              label: 'Abrir',
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );

        return false;
      }

      final posicao = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return false;

      setState(() {
        latitude = posicao.latitude;
        longitude = posicao.longitude;
      });

      return true;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao obter localização: $e')));

      return false;
    } finally {
      if (mounted) {
        setState(() {
          buscandoLocalizacao = false;
        });
      }
    }
  }

  Future<void> finalizar() async {
    if (enviando) return;

    if (foto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tipoFinalizacao == 'ENTREGUE'
                ? 'Tire uma foto para comprovar a entrega.'
                : 'Tire uma foto do local para comprovar a tentativa.',
          ),
        ),
      );

      return;
    }

    if (tipoFinalizacao == 'NAO_ENTREGUE' &&
        justificativaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escreva uma justificativa para a não entrega.'),
        ),
      );

      return;
    }

    final localizacaoObtida = await obterLocalizacao();

    if (!localizacaoObtida || latitude == null || longitude == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível obter sua localização. '
            'Tente novamente.',
          ),
        ),
      );

      return;
    }

    if (!mounted) return;

    setState(() {
      enviando = true;
    });

    Map<String, dynamic>? resultado;

    try {
      if (tipoFinalizacao == 'ENTREGUE') {
        resultado = await ApiService.concluirEntrega(
          id: widget.entregaId,
          caminhoFoto: foto!.path,
          latitude: latitude!,
          longitude: longitude!,
          observacao: observacaoController.text.trim(),
        );
      } else {
        resultado = await ApiService.registrarNaoEntrega(
          id: widget.entregaId,
          caminhoFoto: foto!.path,
          motivo: motivoSelecionado,
          justificativa: justificativaController.text.trim(),
          latitude: latitude!,
          longitude: longitude!,
        );
      }
    } catch (e) {
      resultado = null;

      debugPrint('Erro ao finalizar entrega: $e');
    }

    if (!mounted) return;

    setState(() {
      enviando = false;
    });

    if (resultado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível registrar a entrega. '
            'Verifique a conexão e tente novamente.',
          ),
        ),
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tipoFinalizacao == 'ENTREGUE'
              ? 'Entrega concluída com sucesso!'
              : 'Tentativa de entrega registrada com sucesso!',
        ),
        backgroundColor: tipoFinalizacao == 'ENTREGUE'
            ? AppColors.success
            : AppColors.warning,
      ),
    );

    Navigator.pop(context, true);
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
          color: selecionado ? color.withOpacity(0.12) : theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selecionado ? color : theme.colorScheme.outlineVariant,
            width: selecionado ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
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

            Radio<String>(
              value: valor,
              groupValue: tipoFinalizacao,
              activeColor: color,
              onChanged: enviando
                  ? null
                  : (novoValor) {
                      if (novoValor == null) {
                        return;
                      }

                      setState(() {
                        tipoFinalizacao = novoValor;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget areaFoto() {
    final theme = Theme.of(context);

    if (foto != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              File(foto!.path),
              height: 230,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: enviando ? null : tirarFoto,
            icon: const Icon(Icons.refresh),
            label: const Text('Tirar outra foto'),
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
          border: Border.all(color: AppColors.primary.withOpacity(0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo, size: 48, color: AppColors.primary),
            const SizedBox(height: 10),
            const Text(
              'Tirar foto',
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
                'A foto será usada como comprovante.',
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
        border: Border.all(color: cor.withOpacity(0.25)),
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
                  : 'Localização ainda não disponível',
              style: TextStyle(fontWeight: FontWeight.w600, color: cor),
            ),
          ),

          if (!possuiLocalizacao && !buscandoLocalizacao)
            IconButton(
              tooltip: 'Tentar novamente',
              onPressed: obterLocalizacao,
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
      appBar: AppBar(title: const Text('Finalizar Entrega'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.35),
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

          if (naoEntregue) ...[
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: motivoSelecionado,
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
                      if (valor == null) {
                        return;
                      }

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
              onPressed: enviando ? null : finalizar,
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
                    ? 'Enviando...'
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
    );
  }
}
