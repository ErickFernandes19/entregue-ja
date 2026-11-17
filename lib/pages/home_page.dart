import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../providers/entregas_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String nome = 'Usuário';
  String? fotoUrl;
  Uint8List? fotoBytes;
  int _requisicaoFoto = 0;
  bool verificandoVinculo = false;
  bool dialogoVinculoAberto = false;
  Timer? _timerAtualizacao;
  bool _atualizandoEntregas = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    carregarNome();
    carregarFoto();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      verificarVinculoPendente();
      atualizarEntregas();
    });
    _timerAtualizacao = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) atualizarEntregas();
    });
  }

  @override
  void dispose() {
    _timerAtualizacao?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      verificarVinculoPendente();
      carregarFoto();
      atualizarEntregas();
    }
  }

  Future<void> atualizarEntregas() async {
    if (!mounted || _atualizandoEntregas) return;
    final provider = context.read<EntregasProvider>();
    if (provider.carregando) return;

    _atualizandoEntregas = true;
    try {
      await provider.carregarEntregasDoBackend();
    } catch (e) {
      debugPrint('Erro ao atualizar o painel do entregador: $e');
    } finally {
      _atualizandoEntregas = false;
    }
  }

  Future<void> carregarNome() async {
    final nomeSalvo = await AuthService.nomeUsuario();

    if (!mounted) return;

    setState(() {
      nome = nomeSalvo ?? 'Usuário';
    });
  }

  String? resolverFoto(String? referencia) {
    final valor = referencia?.trim() ?? '';
    if (valor.isEmpty) return null;

    final uri = Uri.tryParse(valor);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      return valor;
    }

    return ApiConfig.urlArquivo(valor);
  }

  Future<void> carregarFoto() async {
    final requisicao = ++_requisicaoFoto;

    try {
      final prefs = await SharedPreferences.getInstance();
      var referencia = prefs.getString('usuario_foto');
      final perfil = await AuthService.buscarPerfil();
      if (!mounted || requisicao != _requisicaoFoto) return;

      if (perfil != null) {
        referencia = perfil['foto']?.toString().trim();
        if (referencia == null || referencia.isEmpty) {
          await prefs.remove('usuario_foto');
        } else {
          await prefs.setString('usuario_foto', referencia);
        }
      }

      final url = resolverFoto(referencia);
      if (url == null) {
        if (!mounted || requisicao != _requisicaoFoto) return;
        setState(() {
          fotoUrl = null;
          fotoBytes = null;
        });
        return;
      }

      final headers = await AuthService.headersAutenticados();
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (!mounted || requisicao != _requisicaoFoto) return;

      if (response.statusCode == 200) {
        setState(() {
          fotoUrl = url;
          fotoBytes = response.bodyBytes;
        });
      } else {
        debugPrint(
          'Erro ao carregar foto na tela inicial: HTTP ${response.statusCode}',
        );
        setState(() {
          fotoUrl = url;
          fotoBytes = null;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar foto do entregador: $e');
    }
  }

  Future<void> verificarVinculoPendente() async {
    if (!mounted || verificandoVinculo || dialogoVinculoAberto) return;

    verificandoVinculo = true;

    try {
      final vinculo = await AuthService.buscarVinculoPendente();

      if (!mounted ||
          vinculo == null ||
          vinculo['possuiVinculo'] != true ||
          dialogoVinculoAberto) {
        return;
      }

      final empresaAtual = await AuthService.buscarEmpresaVinculada();
      if (!mounted || empresaAtual?['vinculado'] == true) return;

      final nomeEmpresa =
          (vinculo['nomeEmpresa'] ??
                  vinculo['empresaNome'] ??
                  vinculo['empresa'] ??
                  'Uma empresa')
              .toString();

      dialogoVinculoAberto = true;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          bool processando = false;

          return StatefulBuilder(
            builder: (context, atualizarDialogo) {
              Future<void> responder(bool aceitar) async {
                if (processando) return;

                atualizarDialogo(() {
                  processando = true;
                });

                bool sucesso = false;
                try {
                  sucesso = aceitar
                      ? await AuthService.aceitarVinculo()
                      : await AuthService.recusarVinculo();
                } catch (e) {
                  debugPrint('Erro ao responder vínculo: $e');
                }

                if (!dialogContext.mounted) return;

                if (sucesso) {
                  Navigator.of(dialogContext).pop();

                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          aceitar
                              ? 'Vínculo aceito com sucesso'
                              : 'Solicitação de vínculo recusada',
                        ),
                      ),
                    );
                  }
                } else {
                  atualizarDialogo(() {
                    processando = false;
                  });

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Não foi possível responder à solicitação. Você pode fechar esta janela e continuar usando o aplicativo.',
                      ),
                    ),
                  );
                }
              }

              return AlertDialog(
                title: const Text('Solicitação de vínculo'),
                content: Text(
                  '$nomeEmpresa deseja vincular você como entregador. Deseja aceitar?',
                ),
                actions: [
                  TextButton(
                    onPressed: processando
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Fechar'),
                  ),
                  TextButton(
                    onPressed: processando ? null : () => responder(false),
                    child: const Text('Recusar'),
                  ),
                  FilledButton(
                    onPressed: processando ? null : () => responder(true),
                    child: processando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Aceitar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      dialogoVinculoAberto = false;
      verificandoVinculo = false;
    }
  }

  Future<void> abrirPagina(String rota) async {
    await context.push(rota);
    if (mounted) await atualizarEntregas();
  }

  Future<void> abrirPerfil() async {
    await context.push('/entregador/perfil');

    if (!mounted) return;
    await carregarFoto();
    await carregarNome();
    await atualizarEntregas();
  }

  String saudacao() {
    final hora = DateTime.now().hour;

    if (hora < 12) return 'Bom dia';
    if (hora < 18) return 'Boa tarde';

    return 'Boa noite';
  }

  Widget header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 46, 18, 24),
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
              abrirPagina('/entregador/configuracoes');
            },
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${saudacao()}, $nome 👋',
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
                  'Vamos organizar suas entregas hoje.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              abrirPerfil();
            },
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 25,
                backgroundColor: Colors.white,
                child: ClipOval(
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: fotoBytes == null
                        ? const Icon(Icons.person, color: AppColors.primary)
                        : Image.memory(
                            fotoBytes!,
                            key: ValueKey(fotoUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.person,
                                color: AppColors.primary,
                              );
                            },
                          ),
                  ),
                ),
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

  Widget acaoRapidaGrande({
    required IconData icon,
    required String titulo,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        height: 96,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EntregasProvider>(context);

    final entregas = provider.entregas
        .where((e) => e.status != 'CANCELADA')
        .toList();

    final totalEntregas = entregas.length;

    final emRota = entregas.where((e) => e.status == 'EM_ROTA').length;

    final entregues = entregas.where((e) => e.status == 'ENTREGUE').length;

    final ganhos = entregas
        .where((e) => e.status == 'ENTREGUE')
        .fold<double>(0, (total, entrega) => total + entrega.valor);

    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          header(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: atualizarEntregas,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    children: [
                      cardResumo(
                        icon: Icons.inventory_2,
                        valor: totalEntregas.toString(),
                        titulo: 'Entregas',
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      cardResumo(
                        icon: Icons.local_shipping,
                        valor: emRota.toString(),
                        titulo: 'Em rota',
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      cardResumo(
                        icon: Icons.check_circle,
                        valor: entregues.toString(),
                        titulo: 'Entregues',
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 12),
                      cardResumo(
                        icon: Icons.attach_money,
                        valor: 'R\$ ${ganhos.toStringAsFixed(2)}',
                        titulo: 'Ganhos',
                        color: Colors.deepPurple,
                      ),
                    ],
                  ),
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
                        icon: Icons.map,
                        titulo: 'Mapa',
                        color: AppColors.primary,
                        onTap: () {
                          abrirPagina('/entregador/mapa');
                        },
                      ),
                      const SizedBox(width: 12),
                      acaoRapida(
                        icon: Icons.inventory_2,
                        titulo: 'Entregas',
                        color: AppColors.success,
                        onTap: () {
                          abrirPagina('/entregador/entregas');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  acaoRapidaGrande(
                    icon: Icons.article,
                    titulo: 'Relatórios',
                    color: Colors.deepPurple,
                    onTap: () {
                      abrirPagina('/entregador/relatorios');
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
