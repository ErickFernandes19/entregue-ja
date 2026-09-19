import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/entregas_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'configuracoes_page.dart';
import 'entregas_page.dart';
import 'mapa_page.dart';
import 'perfil_page.dart';
import 'relatorio_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String nome = 'Usuário';

  @override
  void initState() {
    super.initState();
    carregarNome();
  }

  Future<void> carregarNome() async {
    final nomeSalvo = await AuthService.nomeUsuario();

    if (!mounted) return;

    setState(() {
      nome = nomeSalvo ?? 'Usuário';
    });
  }

  void abrirPagina(BuildContext context, Widget pagina) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => pagina));
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
              abrirPagina(context, const ConfiguracoesPage());
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
              abrirPagina(context, const PerfilPage());
            },
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: const CircleAvatar(
                radius: 25,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: AppColors.primary),
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
          border: Border.all(color: color.withOpacity(0.22)),
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
            child: ListView(
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
                        abrirPagina(context, const MapaPage());
                      },
                    ),

                    const SizedBox(width: 12),

                    acaoRapida(
                      icon: Icons.inventory_2,
                      titulo: 'Entregas',
                      color: AppColors.success,
                      onTap: () {
                        abrirPagina(context, const EntregasPage());
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
                    abrirPagina(context, const RelatorioPage());
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
