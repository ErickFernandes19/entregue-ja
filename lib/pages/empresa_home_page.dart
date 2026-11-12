import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/empresa_estatisticas_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class EmpresaHomePage extends StatefulWidget {
  const EmpresaHomePage({super.key});

  @override
  State<EmpresaHomePage> createState() => _EmpresaHomePageState();
}

class _EmpresaHomePageState extends State<EmpresaHomePage> {
  String nomeEmpresa = 'Empresa';
  Uint8List? fotoEmpresaBytes;
  Timer? timer;
  Map<String, dynamic>? estatisticas;
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    carregarNomeEmpresa();
    carregarFotoEmpresa();
    carregarDados();

    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      carregarDados();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> carregarNomeEmpresa() async {
    final nome = await EmpresaService.nomeEmpresa();

    if (!mounted) return;

    setState(() {
      nomeEmpresa = nome ?? 'Empresa';
    });
  }

  Future<void> carregarFotoEmpresa() async {
    final referencia = await EmpresaService.fotoEmpresa();
    Uint8List? bytes;

    if (referencia != null && referencia.isNotEmpty) {
      bytes = await EmpresaService.buscarBytesFotoEmpresa(referencia);
    }

    if (!mounted) return;

    setState(() {
      fotoEmpresaBytes = bytes;
    });
  }

  Future<void> carregarDados() async {
    final resultado = await EmpresaEstatisticasService.buscarEstatisticas();

    if (!mounted) return;

    setState(() {
      estatisticas = resultado;
      carregando = false;
    });
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
                color: Colors.white.withOpacity(0.25),
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
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: color.withOpacity(0.18),
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
            border: Border.all(color: color.withOpacity(0.22)),
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
    final total = estatisticas?['total']?.toString() ?? '0';

    final entregues = estatisticas?['entregues']?.toString() ?? '0';

    final pendentes = estatisticas?['pendentes']?.toString() ?? '0';

    final emRota = estatisticas?['emRota']?.toString() ?? '0';

    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
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
    );
  }
}
