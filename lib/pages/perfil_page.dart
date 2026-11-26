import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  String nome = 'Entregador';
  String email = '';
  String? fotoUrl;
  Uint8List? fotoBytes;
  bool carregandoFoto = false;
  bool carregandoPerfil = false;
  String? erroPerfil;
  String? erroVinculo;
  String? erroFoto;
  int versaoFoto = 0;
  Map<String, dynamic>? empresaVinculada;
  bool carregandoVinculo = true;
  bool desvinculando = false;
  int versaoVinculo = 0;

  final ImagePicker picker = ImagePicker();
  bool enviandoFoto = false;

  String? resolverFoto(String? referencia) {
    final valor = referencia?.trim() ?? '';
    if (valor.isEmpty) return null;
    final uri = Uri.tryParse(valor);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return valor;
    }
    return ApiConfig.urlArquivo(valor);
  }

  @override
  void initState() {
    super.initState();
    carregarDadosUsuario();
  }

  void mostrarMensagem(String mensagem, {bool sucesso = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: sucesso ? AppColors.success : AppColors.error,
        ),
      );
  }

  Future<void> carregarDadosUsuario() async {
    if (!mounted || carregandoPerfil || desvinculando || enviandoFoto) return;
    setState(() {
      carregandoPerfil = true;
      erroPerfil = null;
    });
    final consultaVinculo = atualizarVinculo();
    try {
      final perfil = await AuthService.buscarPerfil(lancarErro: true);
      if (!mounted) return;
      if (perfil == null) {
        throw const ApiException('Não foi possível carregar o perfil.');
      }
      final referencia = resolverFoto(perfil['foto']?.toString());
      setState(() {
        nome = perfil['nome']?.toString() ?? 'Entregador';
        email = perfil['email']?.toString() ?? '';
      });
      await carregarFotoAutenticada(referencia);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        erroPerfil = ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível carregar o perfil. Tente novamente.',
        );
        if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
          nome = 'Entregador';
          email = '';
          fotoUrl = null;
          fotoBytes = null;
          erroFoto = null;
          versaoFoto++;
          carregandoFoto = false;
        }
      });
    } finally {
      await consultaVinculo;
      if (mounted) setState(() => carregandoPerfil = false);
    }
  }

  Future<void> atualizarVinculo() async {
    if (!mounted) return;
    final requisicao = ++versaoVinculo;
    setState(() {
      carregandoVinculo = true;
      erroVinculo = null;
    });
    try {
      final empresa = await AuthService.buscarEmpresaVinculada(
        lancarErro: true,
      );
      if (empresa == null || empresa['vinculado'] is! bool) {
        throw const FormatException('Resposta de vínculo inválida.');
      }
      if (!mounted || requisicao != versaoVinculo) return;
      setState(() => empresaVinculada = empresa);
    } catch (e) {
      if (!mounted || requisicao != versaoVinculo) return;
      setState(() {
        erroVinculo = ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível consultar a empresa vinculada.',
        );
        if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
          empresaVinculada = null;
        }
      });
    } finally {
      if (mounted && requisicao == versaoVinculo) {
        setState(() => carregandoVinculo = false);
      }
    }
  }

  Future<void> desvincularEmpresa() async {
    if (desvinculando ||
        carregandoVinculo ||
        carregandoPerfil ||
        enviandoFoto ||
        erroVinculo != null ||
        erroPerfil != null ||
        empresaVinculada?['vinculado'] != true) {
      return;
    }

    final nomeEmpresa = empresaVinculada?['nome']?.toString() ?? 'a empresa';
    final emailEmpresa = empresaVinculada?['email']?.toString().trim() ?? '';
    if (emailEmpresa.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível identificar a empresa. Atualize o vínculo.',
          ),
        ),
      );
      await atualizarVinculo();
      return;
    }

    setState(() {
      desvinculando = true;
    });

    try {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Desvincular empresa'),
          content: Text(
            'Deseja encerrar seu vínculo com $nomeEmpresa? '
            'Você voltará a atuar como entregador autônomo e seu histórico '
            'será preservado. Entregas pendentes ou em rota desta empresa '
            'impedem a desvinculação.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Desvincular'),
            ),
          ],
        ),
      );

      if (!mounted || confirmar != true) return;

      final resultado = await AuthService.desvincularEmpresa(
        empresaEmail: emailEmpresa,
      );
      if (!mounted) return;

      final sucesso = resultado['sucesso'] == true;
      final mensagem =
          resultado['mensagem']?.toString() ??
          'Não foi possível confirmar o encerramento do vínculo.';

      if (sucesso) {
        ++versaoVinculo;
        setState(() {
          empresaVinculada = {'vinculado': false};
          erroVinculo = null;
          carregandoVinculo = false;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: sucesso ? AppColors.success : AppColors.error,
        ),
      );

      if (!sucesso) await atualizarVinculo();
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível confirmar o encerramento do vínculo. Atualize o perfil.',
        ),
      );
      await atualizarVinculo();
    } finally {
      if (mounted) {
        setState(() {
          desvinculando = false;
        });
      }
    }
  }

  Future<void> carregarFotoAutenticada(String? url) async {
    if (!mounted) return;
    final requisicao = ++versaoFoto;
    if (url == null) {
      setState(() {
        fotoUrl = null;
        fotoBytes = null;
        erroFoto = null;
        carregandoFoto = false;
      });
      return;
    }
    setState(() {
      if (fotoUrl != url) fotoBytes = null;
      fotoUrl = url;
      erroFoto = null;
      carregandoFoto = true;
    });
    try {
      final uri = Uri.parse(url);
      final apiUri = Uri.parse(ApiConfig.auth);
      final headers = uri.origin == apiUri.origin
          ? await AuthService.headersAutenticados()
          : <String, String>{};
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw ApiService.erroHttp(response.statusCode, response.body);
      }
      if (response.bodyBytes.isEmpty) {
        throw const ApiException('A foto do perfil está indisponível.');
      }
      if (!mounted || requisicao != versaoFoto) return;
      setState(() => fotoBytes = response.bodyBytes);
    } catch (e) {
      if (!mounted || requisicao != versaoFoto) return;
      setState(() {
        erroFoto = ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível carregar a foto do perfil.',
        );
        if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
          fotoBytes = null;
        }
      });
    } finally {
      if (mounted && requisicao == versaoFoto) {
        setState(() => carregandoFoto = false);
      }
    }
  }

  Future<void> escolherFoto(ImageSource source) async {
    if (!mounted ||
        enviandoFoto ||
        carregandoPerfil ||
        desvinculando ||
        erroPerfil != null) {
      return;
    }
    setState(() => enviandoFoto = true);
    try {
      final imagem = await picker.pickImage(source: source, imageQuality: 70);
      if (imagem == null || !mounted) return;
      final bytes = await imagem.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        throw const ApiException('Selecione uma foto válida.');
      }
      final foto = await AuthService.atualizarFotoPerfilBytes(
        bytes: bytes,
        nomeArquivo: imagem.name,
        lancarErro: true,
      );
      if (!mounted) return;
      final url = resolverFoto(foto);
      if (url == null) {
        throw const FormatException('Referência da foto ausente.');
      }
      ++versaoFoto;
      setState(() {
        fotoUrl = url;
        fotoBytes = bytes;
        erroFoto = null;
        carregandoFoto = false;
      });
      mostrarMensagem('Foto atualizada com sucesso.', sucesso: true);
    } on PlatformException catch (e) {
      if (!mounted) return;
      final codigo = e.code.toLowerCase();
      if (codigo.contains('access_denied') || codigo.contains('restricted')) {
        mostrarMensagem(
          source == ImageSource.camera
              ? 'Permita o acesso à câmera nas configurações do dispositivo.'
              : 'Permita o acesso às fotos nas configurações do dispositivo.',
        );
      } else {
        mostrarMensagem('Não foi possível acessar a imagem. Tente novamente.');
      }
    } catch (e) {
      mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível atualizar a foto do perfil.',
        ),
      );
    } finally {
      if (mounted) setState(() => enviandoFoto = false);
    }
  }

  Future<void> abrirOpcoesFoto() async {
    if (enviandoFoto ||
        carregandoPerfil ||
        desvinculando ||
        erroPerfil != null) {
      return;
    }
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final theme = Theme.of(context);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              children: [
                ListTile(
                  title: Text(
                    'Foto de perfil',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Escolha uma opção',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.photo_camera,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    'Tirar foto',
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    escolherFoto(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.photo_library,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    'Escolher da galeria',
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    escolherFoto(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> editarPerfil() async {
    if (carregandoPerfil ||
        enviandoFoto ||
        desvinculando ||
        erroPerfil != null) {
      return;
    }
    await context.push(
      '/entregador/perfil/editar',
      extra: {'nome': nome, 'email': email},
    );

    if (!mounted) return;
    await carregarDadosUsuario();
  }

  Widget avatarPerfil() {
    final theme = Theme.of(context);

    return Center(
      child: GestureDetector(
        onTap:
            enviandoFoto ||
                carregandoPerfil ||
                desvinculando ||
                erroPerfil != null
            ? null
            : abrirOpcoesFoto,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.30 : 0.16,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 62,
                backgroundColor: theme.cardColor,
                child: ClipOval(
                  child: fotoBytes != null
                      ? Image.memory(
                          fotoBytes!,
                          width: 124,
                          height: 124,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.person,
                                color: AppColors.primary,
                                size: 64,
                              ),
                        )
                      : carregandoFoto
                      ? const CircularProgressIndicator()
                      : const Icon(
                          Icons.person,
                          color: AppColors.primary,
                          size: 64,
                        ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.cardColor, width: 3),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget cardInfo({
    required IconData icon,
    required String titulo,
    required String valor,
    required Color color,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          valor.isEmpty ? 'Não informado' : valor,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: onTap == null
            ? null
            : Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }

  Widget cardEmpresaVinculada() {
    if (carregandoVinculo) {
      return cardInfo(
        icon: Icons.business,
        titulo: 'Empresa vinculada',
        valor: 'Consultando vínculo...',
        color: AppColors.primary,
      );
    }

    if (erroVinculo != null || empresaVinculada?['vinculado'] is! bool) {
      return cardInfo(
        icon: Icons.refresh,
        titulo: 'Empresa vinculada',
        valor:
            '${erroVinculo ?? 'Não foi possível consultar o vínculo.'} Toque para tentar novamente.',
        color: AppColors.warning,
        onTap: desvinculando || carregandoPerfil ? null : atualizarVinculo,
      );
    }

    final vinculado = empresaVinculada?['vinculado'] == true;

    if (!vinculado) {
      return cardInfo(
        icon: Icons.business,
        titulo: 'Empresa vinculada',
        valor: 'Nenhuma empresa vinculada no momento',
        color: AppColors.warning,
      );
    }

    final nomeEmpresa = empresaVinculada?['nome'] ?? 'Empresa';
    final emailEmpresa = empresaVinculada?['email'] ?? '';

    return cardInfo(
      icon: Icons.business,
      titulo: nomeEmpresa.toString(),
      valor: emailEmpresa.toString().isEmpty
          ? 'Empresa vinculada'
          : emailEmpresa.toString(),
      color: AppColors.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar ao início',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/entregador/inicio');
            }
          },
        ),
        title: const Text('Meu Perfil'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (carregandoPerfil) const LinearProgressIndicator(),
          if (erroPerfil != null)
            cardInfo(
              icon: Icons.refresh,
              titulo: 'Atualizar perfil',
              valor: erroPerfil!,
              color: AppColors.warning,
              onTap: carregandoPerfil ? null : carregarDadosUsuario,
            ),
          avatarPerfil(),
          if (erroFoto != null)
            TextButton.icon(
              onPressed:
                  carregandoFoto ||
                      enviandoFoto ||
                      carregandoPerfil ||
                      erroPerfil != null
                  ? null
                  : () => carregarFotoAutenticada(fotoUrl),
              icon: const Icon(Icons.refresh),
              label: Text('${erroFoto!} Tentar novamente'),
            ),

          const SizedBox(height: 20),

          Center(
            child: Text(
              nome,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),

          if (email.isNotEmpty) ...[
            const SizedBox(height: 6),

            Center(
              child: Text(
                email,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],

          const SizedBox(height: 28),

          cardEmpresaVinculada(),

          if (empresaVinculada?['vinculado'] == true &&
              !carregandoVinculo &&
              erroVinculo == null) ...[
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed:
                    desvinculando ||
                        carregandoPerfil ||
                        enviandoFoto ||
                        erroPerfil != null
                    ? null
                    : desvincularEmpresa,
                icon: desvinculando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_off),
                label: Text(
                  desvinculando
                      ? 'Encerrando vínculo...'
                      : 'Desvincular empresa',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          cardInfo(
            icon: Icons.person,
            titulo: 'Nome',
            valor: nome,
            color: AppColors.primary,
          ),

          cardInfo(
            icon: Icons.email,
            titulo: 'E-mail',
            valor: email,
            color: Colors.deepPurple,
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed:
                  desvinculando ||
                      carregandoPerfil ||
                      enviandoFoto ||
                      erroPerfil != null
                  ? null
                  : editarPerfil,
              icon: const Icon(Icons.edit),
              label: const Text('Editar Perfil'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed:
                  desvinculando ||
                      carregandoPerfil ||
                      enviandoFoto ||
                      erroPerfil != null
                  ? null
                  : abrirOpcoesFoto,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Alterar Foto'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.brightness == Brightness.dark
                    ? AppColors.primaryLight
                    : AppColors.primary,
                side: BorderSide(
                  color: theme.brightness == Brightness.dark
                      ? AppColors.primaryLight
                      : AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
