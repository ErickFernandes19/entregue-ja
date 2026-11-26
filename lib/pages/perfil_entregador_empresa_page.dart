import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class PerfilEntregadorEmpresaPage extends StatefulWidget {
  final Map<String, dynamic> entregador;

  const PerfilEntregadorEmpresaPage({super.key, required this.entregador});

  @override
  State<PerfilEntregadorEmpresaPage> createState() =>
      _PerfilEntregadorEmpresaPageState();
}

class _PerfilEntregadorEmpresaPageState
    extends State<PerfilEntregadorEmpresaPage> {
  Uint8List? fotoBytes;
  bool carregandoFoto = false;
  bool _desvinculando = false;
  bool _abrindoEntregas = false;
  bool _sessaoIndisponivel = false;
  int _versaoFoto = 0;
  late final Future<String> _tokenInicial;

  @override
  void initState() {
    super.initState();
    _tokenInicial = _obterTokenValido();
    carregarFoto();
  }

  @override
  void didUpdateWidget(covariant PerfilEntregadorEmpresaPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.entregador['foto'] != widget.entregador['foto'] ||
        oldWidget.entregador['email'] != widget.entregador['email']) {
      carregarFoto();
    }
  }

  @override
  void dispose() {
    _versaoFoto++;
    super.dispose();
  }

  String get _emailEntregador =>
      widget.entregador['email']?.toString().trim() ?? '';

  Future<String> _obterTokenValido() async {
    final empresa = await EmpresaService.empresaLogada();
    final token = await EmpresaService.obterTokenEmpresa();
    if (empresa == null ||
        empresa.trim().isEmpty ||
        token == null ||
        token.trim().isEmpty) {
      throw const ApiException(
        'Sua sessão expirou. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
    return token;
  }

  Future<String> _validarSessao() async {
    final inicial = await _tokenInicial;
    final atual = await _obterTokenValido();
    if (atual != inicial) {
      throw const ApiException(
        'Sua sessão mudou. Volte à lista de entregadores e atualize os dados.',
        statusCode: 401,
      );
    }
    return atual;
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: AppColors.error),
    );
  }

  void _tratarErro(Object erro, String mensagemPadrao) {
    if (!mounted) return;
    if (erro is ApiException && erro.statusCode == 401) {
      if (_sessaoIndisponivel) return;
      setState(() {
        _sessaoIndisponivel = true;
        fotoBytes = null;
        carregandoFoto = false;
        _versaoFoto++;
      });
    }
    _mostrarErro(ApiService.mensagemErro(erro, mensagemPadrao: mensagemPadrao));
  }

  Future<http.Response> _baixarFoto(Uri uri, String token) async {
    final apiUri = Uri.parse(ApiConfig.empresas);
    final cliente = http.Client();
    try {
      final requisicao = http.Request('GET', uri);
      if (uri.origin == apiUri.origin) {
        requisicao.headers['Authorization'] = 'Bearer $token';
        requisicao.followRedirects = false;
      }
      final resposta = await cliente.send(requisicao);
      return await http.Response.fromStream(resposta);
    } finally {
      cliente.close();
    }
  }

  Future<void> carregarFoto() async {
    if (!mounted || _sessaoIndisponivel) return;
    final versao = ++_versaoFoto;
    final referencia = widget.entregador['foto']?.toString().trim() ?? '';

    setState(() {
      fotoBytes = null;
      carregandoFoto = referencia.isNotEmpty;
    });

    try {
      final token = await _validarSessao();
      if (!mounted || versao != _versaoFoto || referencia.isEmpty) return;

      final url =
          referencia.startsWith('http://') || referencia.startsWith('https://')
          ? referencia
          : ApiConfig.urlArquivo(referencia);
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.userInfo.isNotEmpty) {
        throw const ApiException(
          'O endereço da foto do entregador é inválido.',
        );
      }

      final resposta = await _baixarFoto(
        uri,
        token,
      ).timeout(const Duration(seconds: 20));
      if (!mounted || versao != _versaoFoto) return;
      await _validarSessao();
      if (!mounted || versao != _versaoFoto) return;

      if (resposta.statusCode != 200) {
        if (uri.origin != Uri.parse(ApiConfig.empresas).origin) {
          throw const ApiException(
            'Não foi possível carregar a foto do entregador.',
          );
        }
        throw ApiService.erroHttp(
          resposta.statusCode,
          utf8.decode(resposta.bodyBytes, allowMalformed: true),
        );
      }
      if (resposta.bodyBytes.isEmpty) {
        throw const ApiException('A foto do entregador está indisponível.');
      }

      try {
        final codec = await ui.instantiateImageCodec(
          resposta.bodyBytes,
          targetWidth: 120,
        );
        try {
          final quadro = await codec.getNextFrame();
          quadro.image.dispose();
        } finally {
          codec.dispose();
        }
      } catch (_) {
        throw const ApiException(
          'Não foi possível abrir a foto do entregador.',
        );
      }
      await _validarSessao();
      if (!mounted || versao != _versaoFoto) return;
      setState(() => fotoBytes = resposta.bodyBytes);
    } catch (e) {
      if (!mounted || versao != _versaoFoto) return;
      _tratarErro(e, 'Não foi possível carregar a foto do entregador.');
    } finally {
      if (mounted && versao == _versaoFoto) {
        setState(() => carregandoFoto = false);
      }
    }
  }

  Future<void> desvincularEntregador() async {
    if (!mounted || _desvinculando || _abrindoEntregas || _sessaoIndisponivel) {
      return;
    }
    final email = _emailEntregador;
    if (email.isEmpty) {
      _mostrarErro('E-mail do entregador não disponível.');
      return;
    }

    setState(() => _desvinculando = true);
    try {
      await _validarSessao();
      if (!mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Desvincular entregador'),
            content: Text(
              'Deseja realmente desvincular '
              '${widget.entregador["nome"] ?? "este entregador"} '
              'da empresa?',
            ),
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
                child: const Text('Desvincular'),
              ),
            ],
          );
        },
      );
      if (!mounted || confirmar != true) return;
      await _validarSessao();
      if (!mounted) return;
      if (email != _emailEntregador) {
        throw const ApiException(
          'Os dados do entregador mudaram. Atualize a lista e tente novamente.',
        );
      }
      final sucesso = await EmpresaService.desvincularEntregador(
        email,
        lancarErro: true,
      );
      if (!mounted) return;
      await _validarSessao();
      if (!mounted) return;
      if (!sucesso) {
        throw const ApiException('Não foi possível desvincular o entregador.');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entregador desvinculado com sucesso')),
      );
      setState(() => _desvinculando = false);
      context.pop(true);
    } catch (e) {
      _tratarErro(
        e,
        'Não foi possível desvincular o entregador. Tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => _desvinculando = false);
      }
    }
  }

  Future<void> _abrirEntregas() async {
    if (!mounted || _abrindoEntregas || _desvinculando || _sessaoIndisponivel) {
      return;
    }
    final email = _emailEntregador;
    if (email.isEmpty) {
      _mostrarErro('E-mail do entregador não disponível');
      return;
    }
    _abrindoEntregas = true;
    try {
      await _validarSessao();
      if (!mounted) return;
      if (email != _emailEntregador) {
        throw const ApiException(
          'Os dados do entregador mudaram. Atualize a lista e tente novamente.',
        );
      }
      final nome = widget.entregador['nome']?.toString() ?? 'Entregador';
      await context.push(
        '/empresa/entregadores/entregas',
        extra: {'entregadorEmail': email, 'entregadorNome': nome},
      );
    } catch (e) {
      _tratarErro(e, 'Não foi possível abrir as entregas do entregador.');
    } finally {
      _abrindoEntregas = false;
    }
  }

  String formatarData(String? data) {
    if (data == null || data.isEmpty) {
      return 'Não informada';
    }

    try {
      final date = DateTime.parse(data);

      final dia = date.day.toString().padLeft(2, '0');
      final mes = date.month.toString().padLeft(2, '0');
      final ano = date.year.toString();

      final hora = date.hour.toString().padLeft(2, '0');
      final minuto = date.minute.toString().padLeft(2, '0');

      return '$dia/$mes/$ano às $hora:$minuto';
    } catch (_) {
      return data;
    }
  }

  Widget cardInfo({
    required BuildContext context,
    required IconData icon,
    required String titulo,
    required String valor,
    required Color color,
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
      ),
    );
  }

  Widget construirFoto(ThemeData theme) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.28 : 0.14,
              ),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: CircleAvatar(
          radius: 60,
          backgroundColor: theme.cardColor,
          child: ClipOval(
            child: SizedBox(
              width: 120,
              height: 120,
              child: carregandoFoto
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : fotoBytes != null
                  ? Image.memory(
                      fotoBytes!,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.person,
                          color: AppColors.primary,
                          size: 60,
                        );
                      },
                    )
                  : const Icon(
                      Icons.person,
                      color: AppColors.primary,
                      size: 60,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final nome = widget.entregador["nome"]?.toString() ?? "Entregador";

    final email = widget.entregador["email"]?.toString() ?? "";

    final veiculo = widget.entregador["veiculo"]?.toString().trim() ?? "";

    final capacidade =
        widget.entregador["capacidadeCarga"]?.toString().trim() ?? "";

    final dataVinculo = widget.entregador["dataVinculo"]?.toString();

    return PopScope(
      canPop: !_desvinculando,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Voltar aos entregadores',
            icon: const Icon(Icons.arrow_back),
            onPressed: _desvinculando
                ? null
                : () {
                    if (context.canPop()) {
                      context.pop(false);
                    } else {
                      context.go('/empresa/entregadores');
                    }
                  },
          ),
          title: const Text('Perfil do Entregador'),
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            construirFoto(theme),
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
            const SizedBox(height: 8),
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
            const SizedBox(height: 25),
            cardInfo(
              context: context,
              icon: Icons.email,
              titulo: 'E-mail',
              valor: email,
              color: Colors.deepPurple,
            ),
            cardInfo(
              context: context,
              icon: Icons.directions_car,
              titulo: 'Veículo',
              valor: veiculo.isEmpty ? 'Não informado' : veiculo,
              color: AppColors.primary,
            ),
            cardInfo(
              context: context,
              icon: Icons.inventory_2,
              titulo: 'Capacidade de carga',
              valor: capacidade.isEmpty ? 'Não informada' : '$capacidade kg',
              color: Colors.orange,
            ),
            cardInfo(
              context: context,
              icon: Icons.calendar_today,
              titulo: 'Vinculado desde',
              valor: formatarData(dataVinculo),
              color: AppColors.success,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 55,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.list_alt),
                label: const Text('Ver Entregas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _desvinculando || _sessaoIndisponivel
                    ? null
                    : _abrirEntregas,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 55,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text('Desvincular Entregador'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: _desvinculando || _sessaoIndisponivel
                    ? null
                    : desvincularEntregador,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
