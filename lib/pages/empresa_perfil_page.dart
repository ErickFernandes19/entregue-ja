import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class EmpresaPerfilPage extends StatefulWidget {
  const EmpresaPerfilPage({super.key});

  @override
  State<EmpresaPerfilPage> createState() => _EmpresaPerfilPageState();
}

class _EmpresaPerfilPageState extends State<EmpresaPerfilPage> {
  String nome = 'Empresa';
  String email = '';
  String? fotoUrl;
  Uint8List? fotoBytes;

  List<dynamic> entregadores = [];

  bool carregando = true;
  bool carregandoFoto = false;
  bool enviandoFoto = false;
  bool _consultandoEmpresa = false;
  bool _abrindoOpcoes = false;
  bool _editandoPerfil = false;
  bool _sessaoIndisponivel = false;
  String? _tokenSessao;
  String? _erroEntregadores;

  bool get _ocupado =>
      _consultandoEmpresa || enviandoFoto || _abrindoOpcoes || _editandoPerfil;

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    carregarEmpresa();
  }

  void _mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<String> _validarSessao() async {
    final empresa = await EmpresaService.empresaLogada();
    final token = await EmpresaService.obterTokenEmpresa();
    if (empresa == null ||
        empresa.trim().isEmpty ||
        token == null ||
        token.trim().isEmpty ||
        (_tokenSessao != null && _tokenSessao != token)) {
      throw const ApiException(
        'Sua sessão expirou ou mudou. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
    _tokenSessao ??= token;
    return empresa;
  }

  void _tratarErro(Object erro, String mensagemPadrao) {
    if (!mounted) return;
    if (erro is ApiException &&
        (erro.statusCode == 401 || erro.statusCode == 403)) {
      setState(() {
        _sessaoIndisponivel = true;
        nome = 'Empresa';
        email = '';
        fotoUrl = null;
        fotoBytes = null;
        entregadores = [];
        _erroEntregadores = 'Não foi possível consultar os entregadores.';
      });
    }
    _mostrarMensagem(
      ApiService.mensagemErro(erro, mensagemPadrao: mensagemPadrao),
    );
  }

  Future<void> carregarEmpresa() async {
    if (!mounted || _ocupado || _sessaoIndisponivel) return;
    _consultandoEmpresa = true;
    try {
      final empresaEmail = await _validarSessao();
      final empresaNome = await EmpresaService.nomeEmpresa();
      final empresaFoto = await EmpresaService.fotoEmpresa();
      await _validarSessao();
      if (!mounted) return;
      setState(() {
        email = empresaEmail;
        nome = empresaNome ?? 'Empresa';
        if (fotoUrl != empresaFoto) fotoBytes = null;
        fotoUrl = empresaFoto;
      });

      try {
        final lista = await EmpresaService.buscarEntregadores(lancarErro: true);
        await _validarSessao();
        if (!mounted) return;
        if (lista.any((item) => item is! Map<String, dynamic>)) {
          throw const FormatException('Lista de entregadores inválida.');
        }
        setState(() {
          entregadores = lista;
          _erroEntregadores = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _erroEntregadores = ApiService.mensagemErro(
            e,
            mensagemPadrao: 'Não foi possível consultar os entregadores.',
          );
        });
        _tratarErro(e, 'Não foi possível consultar os entregadores.');
      }

      if (!mounted || _sessaoIndisponivel) return;
      setState(() => carregando = false);
      await carregarFoto(empresaFoto);
    } catch (e) {
      _tratarErro(e, 'Não foi possível carregar o perfil da empresa.');
      if (mounted) {
        setState(() {
          _erroEntregadores ??= 'Não foi possível consultar os entregadores.';
        });
      }
    } finally {
      _consultandoEmpresa = false;
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> _validarImagem(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const ApiException('A imagem está vazia ou indisponível.');
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 120);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } catch (_) {
      throw const ApiException(
        'Não foi possível abrir a imagem. Confira o formato.',
      );
    }
  }

  Future<void> carregarFoto(String? referencia) async {
    if (!mounted || _sessaoIndisponivel) return;
    if (referencia == null || referencia.trim().isEmpty) {
      setState(() {
        fotoBytes = null;
        carregandoFoto = false;
      });
      return;
    }
    setState(() => carregandoFoto = true);
    final cliente = http.Client();
    try {
      await _validarSessao();
      final uri = Uri.tryParse(EmpresaService.urlFotoEmpresa(referencia));
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const ApiException('O endereço do logo da empresa é inválido.');
      }
      final apiUri = Uri.parse(ApiConfig.empresas);
      final requisicao = http.Request('GET', uri);
      final mesmaOrigem = uri.origin == apiUri.origin;
      if (mesmaOrigem) {
        requisicao.headers['Authorization'] = 'Bearer ${_tokenSessao!}';
        requisicao.followRedirects = false;
      }
      final resposta = await cliente
          .send(requisicao)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      if (resposta.statusCode != 200) {
        if (mesmaOrigem) {
          throw ApiService.erroHttp(resposta.statusCode, resposta.body);
        }
        throw const ApiException(
          'Não foi possível carregar o logo da empresa.',
        );
      }
      await _validarImagem(resposta.bodyBytes);
      await _validarSessao();
      if (!mounted) return;
      setState(() => fotoBytes = resposta.bodyBytes);
    } catch (e) {
      _tratarErro(e, 'Não foi possível carregar o logo da empresa.');
    } finally {
      cliente.close();
      if (mounted) setState(() => carregandoFoto = false);
    }
  }

  Future<void> escolherFoto(ImageSource source) async {
    if (!mounted || _ocupado || _sessaoIndisponivel) return;
    setState(() => enviandoFoto = true);
    try {
      await _validarSessao();
      if (!mounted) return;
      final imagem = await picker.pickImage(source: source, imageQuality: 70);
      if (imagem == null || !mounted) return;
      final bytes = await imagem.readAsBytes();
      await _validarImagem(bytes);
      await _validarSessao();
      if (!mounted) return;

      final nomeArquivo = imagem.name;
      final nomeMinusculo = nomeArquivo.toLowerCase();
      if (!nomeMinusculo.endsWith('.jpg') &&
          !nomeMinusculo.endsWith('.jpeg') &&
          !nomeMinusculo.endsWith('.png') &&
          !nomeMinusculo.endsWith('.webp')) {
        throw const ApiException('Escolha uma imagem JPG, PNG ou WEBP.');
      }
      final foto = await EmpresaService.atualizarFotoEmpresaBytes(
        bytes: bytes,
        nomeArquivo: nomeArquivo,
        lancarErro: true,
      );
      await _validarSessao();
      if (!mounted) return;
      if (foto == null || foto.trim().isEmpty) {
        throw const ApiException(
          'Não foi possível confirmar a atualização do logo.',
        );
      }
      setState(() {
        fotoUrl = foto;
        fotoBytes = bytes;
      });
      _mostrarMensagem('Foto atualizada com sucesso');
    } on PlatformException catch (e) {
      final codigo = e.code.toLowerCase();
      if (codigo.contains('access_denied') ||
          codigo.contains('restricted') ||
          codigo.contains('permission')) {
        _mostrarMensagem(
          source == ImageSource.camera
              ? 'Permita o acesso à câmera nas configurações do dispositivo.'
              : 'Permita o acesso às fotos nas configurações do dispositivo.',
        );
      } else {
        _mostrarMensagem('Não foi possível acessar a imagem. Tente novamente.');
      }
    } catch (e) {
      _tratarErro(e, 'Não foi possível atualizar o logo da empresa.');
    } finally {
      if (mounted) setState(() => enviandoFoto = false);
    }
  }

  Future<void> abrirOpcoesFoto() async {
    if (!mounted || _ocupado || _sessaoIndisponivel) return;
    _abrindoOpcoes = true;
    ImageSource? source;
    try {
      source = await showModalBottomSheet<ImageSource>(
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
                      'Logo da empresa',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      'Escolha uma opção',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
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
                      Navigator.pop(context, ImageSource.camera);
                    },
                  ),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
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
                      Navigator.pop(context, ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      _tratarErro(e, 'Não foi possível abrir as opções de foto.');
    } finally {
      _abrindoOpcoes = false;
    }
    if (mounted && source != null) await escolherFoto(source);
  }

  Future<void> editarPerfil() async {
    if (!mounted || _ocupado || _sessaoIndisponivel) return;
    _editandoPerfil = true;
    bool? atualizado;
    try {
      await _validarSessao();
      if (!mounted) return;
      atualizado = await context.push<bool>(
        '/empresa/perfil/editar',
        extra: {'nome': nome, 'email': email},
      );
    } catch (e) {
      _tratarErro(e, 'Não foi possível abrir a edição do perfil.');
    } finally {
      _editandoPerfil = false;
    }
    if (mounted && atualizado == true) await carregarEmpresa();
  }

  Widget avatarEmpresa() {
    final theme = Theme.of(context);

    return Center(
      child: GestureDetector(
        onTap: enviandoFoto || _sessaoIndisponivel ? null : abrirOpcoesFoto,
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
                backgroundImage: fotoBytes == null
                    ? null
                    : MemoryImage(fotoBytes!),
                child: enviandoFoto || carregandoFoto
                    ? const CircularProgressIndicator(color: AppColors.primary)
                    : fotoBytes == null
                    ? const Icon(
                        Icons.business,
                        color: AppColors.primary,
                        size: 64,
                      )
                    : null,
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

  Widget cardEntregador(dynamic entregador) {
    final theme = Theme.of(context);

    final nomeEntregador = entregador['nome'] ?? 'Entregador';

    final emailEntregador = entregador['email'] ?? 'E-mail não informado';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.16 : 0.04,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.14),
          child: const Icon(Icons.person, color: AppColors.primary),
        ),
        title: Text(
          nomeEntregador.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          emailEntregador.toString(),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
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
            context.go('/empresa/inicio');
          },
        ),
        title: const Text('Perfil da Empresa'),
        centerTitle: true,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: carregarEmpresa,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  avatarEmpresa(),

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

                  const SizedBox(height: 6),

                  Center(
                    child: Text(
                      email.isEmpty ? 'E-mail não informado' : email,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  cardInfo(
                    icon: Icons.business,
                    titulo: 'Nome da empresa',
                    valor: nome,
                    color: AppColors.primary,
                  ),

                  cardInfo(
                    icon: Icons.email,
                    titulo: 'E-mail',
                    valor: email,
                    color: Colors.deepPurple,
                  ),

                  cardInfo(
                    icon: Icons.groups,
                    titulo: 'Entregadores vinculados',
                    valor: _erroEntregadores != null
                        ? 'Consulta indisponível'
                        : '${entregadores.length} entregador(es)',
                    color: Colors.orange,
                  ),

                  const SizedBox(height: 8),

                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: enviandoFoto || _sessaoIndisponivel
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
                      onPressed: enviandoFoto || _sessaoIndisponivel
                          ? null
                          : abrirOpcoesFoto,
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Alterar Logo'),
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

                  const SizedBox(height: 24),

                  Text(
                    'Entregadores',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (entregadores.isEmpty)
                    cardInfo(
                      icon: Icons.person_off,
                      titulo: _erroEntregadores == null
                          ? 'Nenhum entregador vinculado'
                          : 'Não foi possível consultar os entregadores',
                      valor: _erroEntregadores == null
                          ? 'Vincule um entregador para ele aparecer aqui.'
                          : 'Deslize para atualizar e tente novamente.',
                      color: Colors.orange,
                    )
                  else
                    ...entregadores.map(cardEntregador),
                ],
              ),
            ),
    );
  }
}
