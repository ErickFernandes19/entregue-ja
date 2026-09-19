import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';

class EmpresaNotificacoesPage extends StatefulWidget {
  const EmpresaNotificacoesPage({super.key});

  @override
  State<EmpresaNotificacoesPage> createState() =>
      _EmpresaNotificacoesPageState();
}

class _EmpresaNotificacoesPageState extends State<EmpresaNotificacoesPage> {
  bool entregaConcluida = true;
  bool entregaCancelada = true;
  bool novoEntregador = true;
  bool solicitacoes = true;
  bool sons = true;
  bool vibracao = true;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      entregaConcluida = prefs.getBool('empresa_entrega_concluida') ?? true;
      entregaCancelada = prefs.getBool('empresa_entrega_cancelada') ?? true;
      novoEntregador = prefs.getBool('empresa_novo_entregador') ?? true;
      solicitacoes = prefs.getBool('empresa_solicitacoes') ?? true;
      sons = prefs.getBool('empresa_sons') ?? true;
      vibracao = prefs.getBool('empresa_vibracao') ?? true;
    });
  }

  Future<void> salvar(String chave, bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(chave, valor);
  }

  Widget opcao({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required bool valor,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              theme.brightness == Brightness.dark ? 0.16 : 0.05,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        secondary: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.14),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          subtitulo,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        value: valor,
        activeColor: AppColors.primary,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Notificações'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Preferências de notificação',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Escolha quais avisos sua empresa deseja receber.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),

          const SizedBox(height: 22),

          opcao(
            icon: Icons.check_circle,
            titulo: 'Entrega concluída',
            subtitulo: 'Receber aviso quando uma entrega for concluída',
            valor: entregaConcluida,
            onChanged: (v) {
              setState(() {
                entregaConcluida = v;
              });

              salvar('empresa_entrega_concluida', v);
            },
          ),

          opcao(
            icon: Icons.cancel,
            titulo: 'Entrega cancelada',
            subtitulo: 'Receber aviso quando uma entrega for cancelada',
            valor: entregaCancelada,
            onChanged: (v) {
              setState(() {
                entregaCancelada = v;
              });

              salvar('empresa_entrega_cancelada', v);
            },
          ),

          opcao(
            icon: Icons.person_add,
            titulo: 'Novo entregador vinculado',
            subtitulo: 'Receber aviso quando um entregador aceitar o vínculo',
            valor: novoEntregador,
            onChanged: (v) {
              setState(() {
                novoEntregador = v;
              });

              salvar('empresa_novo_entregador', v);
            },
          ),

          opcao(
            icon: Icons.pending_actions,
            titulo: 'Solicitações pendentes',
            subtitulo: 'Receber aviso sobre novas solicitações',
            valor: solicitacoes,
            onChanged: (v) {
              setState(() {
                solicitacoes = v;
              });

              salvar('empresa_solicitacoes', v);
            },
          ),

          const SizedBox(height: 10),

          Text(
            'Comportamento',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 12),

          opcao(
            icon: Icons.volume_up,
            titulo: 'Sons',
            subtitulo: 'Emitir som nas notificações',
            valor: sons,
            onChanged: (v) {
              setState(() {
                sons = v;
              });

              salvar('empresa_sons', v);
            },
          ),

          opcao(
            icon: Icons.vibration,
            titulo: 'Vibração',
            subtitulo: 'Vibrar ao receber notificações',
            valor: vibracao,
            onChanged: (v) {
              setState(() {
                vibracao = v;
              });

              salvar('empresa_vibracao', v);
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
