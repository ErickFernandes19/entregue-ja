import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/empresa_estatisticas_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class EmpresaHomePage extends StatefulWidget {
  const EmpresaHomePage({super.key});

  @override
  State<EmpresaHomePage> createState() => _EmpresaHomePageState();
}

class _EmpresaHomePageState extends State<EmpresaHomePage>
    with WidgetsBindingObserver {
  String nomeEmpresa = 'Empresa';
  Uint8List? fotoEmpresaBytes;
  Timer? timer;
  Map<String, dynamic>? estatisticas;
  bool carregando = true;
  Future<void>? _consultaDados;
  String? _ultimoErroEstatisticas;
  bool _appAtivo = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(carregarNomeEmpresa());
    unawaited(carregarFotoEmpresa());
    unawaited(carregarDados());

    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_appAtivo) {
        unawaited(carregarDados(automatico: true));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ativo = state == AppLifecycleState.resumed;
    if (ativo && !_appAtivo) {
      unawaited(carregarDados(automatico: true));
    }
    _appAtivo = ativo;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  bool _mostrarMensagem(String mensagem) {
    if (!mounted || !_appAtivo || ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return false;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(mensagem)));
    return true;
  }

  Future<void> carregarNomeEmpresa() async {
    try {
      final nome = await EmpresaService.nomeEmpresa();
      if (!mounted) return;

      setState(() {
        nomeEmpresa = nome ?? 'Empresa';
      });
    } catch (e) {
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível carregar o nome da empresa.',
        ),
      );
    }
  }

  Future<void> carregarFotoEmpresa() async {
    try {
      final referencia = await EmpresaService.fotoEmpresa();
      if (!mounted) return;

      Uint8List? bytes;
      if (referencia != null && referencia.trim().isNotEmpty) {
        bytes = await EmpresaService.buscarBytesFotoEmpresa(
          referencia,
          lancarErro: true,
        );
        if (bytes == null || bytes.isEmpty) {
          throw const ApiException(
            'Não foi possível carregar a foto da empresa.',
          );
        }
      }

      if (!mounted) return;
      setState(() {
        fotoEmpresaBytes = bytes;
      });
    } catch (e) {
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível carregar a foto da empresa.',
        ),
      );
    }
  }

  Future<void> carregarDados({bool automatico = false}) {
    if (!mounted) return Future<void>.value();

    final consultaAtual = _consultaDados;
    if (consultaAtual != null) return consultaAtual;

    final consulta = _carregarDados(automatico).whenComplete(() {
      _consultaDados = null;
    });
    _consultaDados = consulta;
    return consulta;
  }

  Future<void> _carregarDados(bool automatico) async {
    try {
      final empresa = await EmpresaService.empresaLogada();
      if (!mounted) return;
      if (empresa == null) {
        throw const ApiException(
          'Sua sessão expirou. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }

      final resultado = await EmpresaEstatisticasService.buscarEstatisticas()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      if (resultado == null) {
        throw const ApiException(
          'Não foi possível atualizar as estatísticas. Verifique sua conexão e tente novamente.',
        );
      }

      const campos = [
        'total',
        'entregues',
        'pendentes',
        'emRota',
        'naoEntregues',
      ];
      final dados = Map<String, dynamic>.from(resultado);
      for (final campo in campos) {
        final valor = int.tryParse(dados[campo]?.toString() ?? '');
        if (valor == null || valor < 0) {
          throw const FormatException('Estatísticas inválidas');
        }
        dados[campo] = valor;
      }

      setState(() {
        estatisticas = dados;
        _ultimoErroEstatisticas = null;
      });
    } catch (e) {
      if (!mounted) return;
      final mensagem = ApiService.mensagemErro(
        e,
        mensagemPadrao:
            'Não foi possível atualizar as estatísticas. Tente novamente.',
      );
      if (!automatico || mensagem != _ultimoErroEstatisticas) {
        final aviso = estatisticas == null
            ? mensagem
            : '$mensagem Os últimos dados disponíveis continuam exibidos.';
        if (_mostrarMensagem(aviso)) {
          _ultimoErroEstatisticas = mensagem;
        }
      }
    } finally {
      if (mounted && carregando) {
        setState(() => carregando = false);
      }
    }
  }

  void abrirPagina(String rota) {
    context.push(rota);
  }

  Future<void> abrirPerfilEmpresa() async {
    await context.push('/empresa/perfil');

    if (!mounted) return;

    await carregarNomeEmpresa();
    await carregarFotoEmpresa();
  }

  Widget header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              abrirPagina('/empresa/configuracoes');
            },
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá, $nomeEmpresa 👋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gerencie entregas e entregadores.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: abrirPerfilEmpresa,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 25,
                backgroundColor: Colors.white,
                backgroundImage: fotoEmpresaBytes == null
                    ? null
                    : MemoryImage(fotoEmpresaBytes!),
                child: fotoEmpresaBytes == null
                    ? const Icon(Icons.business, color: AppColors.primary)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget cardResumo({
    required IconData icon,
    required String valor,
    required String titulo,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        height: 82,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget acaoRapida({
    required IconData icon,
    required String titulo,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 112,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(height: 10),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = estatisticas?['total']?.toString() ?? '—';

    final entregues = estatisticas?['entregues']?.toString() ?? '—';

    final pendentes = estatisticas?['pendentes']?.toString() ?? '—';

    final emRota = estatisticas?['emRota']?.toString() ?? '—';

    final naoEntregues = estatisticas?['naoEntregues']?.toString() ?? '—';

    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            header(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: carregarDados,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(18),
                  children: [
                    if (carregando)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      Row(
                        children: [
                          cardResumo(
                            icon: Icons.inventory_2,
                            valor: total,
                            titulo: 'Total',
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          cardResumo(
                            icon: Icons.local_shipping,
                            valor: emRota,
                            titulo: 'Em rota',
                            color: Colors.blue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          cardResumo(
                            icon: Icons.check_circle,
                            valor: entregues,
                            titulo: 'Entregues',
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 12),
                          cardResumo(
                            icon: Icons.pending,
                            valor: pendentes,
                            titulo: 'Pendentes',
                            color: AppColors.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          cardResumo(
                            icon: Icons.report_problem_outlined,
                            valor: naoEntregues,
                            titulo: 'Não entregues',
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 12),
                          const Spacer(),
                        ],
                      ),
                    ],

                    const SizedBox(height: 22),

                    Text(
                      'Ações rápidas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        acaoRapida(
                          icon: Icons.add_box,
                          titulo: 'Cadastrar\nEntrega',
                          color: AppColors.primary,
                          onTap: () async {
                            await context.push('/empresa/cadastrar-entrega');

                            await carregarDados();
                          },
                        ),
                        const SizedBox(width: 12),
                        acaoRapida(
                          icon: Icons.inventory,
                          titulo: 'Minhas\nEntregas',
                          color: AppColors.warning,
                          onTap: () async {
                            await context.push('/empresa/entregas');

                            await carregarDados();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        acaoRapida(
                          icon: Icons.person_add,
                          titulo: 'Vincular\nEntregador',
                          color: AppColors.success,
                          onTap: () async {
                            await context.push('/empresa/vincular-entregador');

                            await carregarDados();
                          },
                        ),
                        const SizedBox(width: 12),
                        acaoRapida(
                          icon: Icons.settings,
                          titulo: 'Configurações',
                          color: Colors.deepPurple,
                          onTap: () {
                            abrirPagina('/empresa/configuracoes');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
