import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';

class NotificacoesPage extends StatefulWidget {
  const NotificacoesPage({super.key});

  @override
  State<NotificacoesPage> createState() => _NotificacoesPageState();
}

class _NotificacoesPageState extends State<NotificacoesPage> {
  bool novasEntregas = true;
  bool statusEntregas = true;
  bool vinculos = true;
  bool sons = true;
  bool vibracao = true;

  bool carregando = true;

  final List<Map<String, dynamic>> notificacoes = [
    {
      'tipo': 'nova_entrega',
      'icone': Icons.inventory_2,
      'cor': AppColors.primary,
      'titulo': 'Nova entrega recebida',
      'tempo': 'Agora mesmo',
      'descricao': 'Uma nova entrega foi adicionada para você.',
      'lida': false,
    },
    {
      'tipo': 'vinculo',
      'icone': Icons.business,
      'cor': Colors.orange,
      'titulo': 'Solicitação de vínculo',
      'tempo': '5 min atrás',
      'descricao': 'Uma empresa enviou uma solicitação de vínculo.',
      'lida': false,
    },
    {
      'tipo': 'status',
      'icone': Icons.check_circle,
      'cor': AppColors.success,
      'titulo': 'Entrega concluída',
      'tempo': 'Hoje',
      'descricao': 'Uma entrega foi marcada como concluída.',
      'lida': true,
    },
  ];

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      novasEntregas = prefs.getBool('notif_novas_entregas') ?? true;

      statusEntregas = prefs.getBool('notif_status_entregas') ?? true;

      vinculos = prefs.getBool('notif_vinculos') ?? true;

      sons = prefs.getBool('notif_sons') ?? true;

      vibracao = prefs.getBool('notif_vibracao') ?? true;

      carregando = false;
    });
  }

  Future<void> salvar(String chave, bool valor) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(chave, valor);
  }

  List<Map<String, dynamic>> get notificacoesVisiveis {
    return notificacoes.where((item) {
      final tipo = item['tipo'];

      if (tipo == 'nova_entrega') {
        return novasEntregas;
      }

      if (tipo == 'status') {
        return statusEntregas;
      }

      if (tipo == 'vinculo') {
        return vinculos;
      }

      return true;
    }).toList();
  }

  Widget opcao({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required bool valor,
    required ValueChanged<bool> onChanged,
    required Color color,
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
          backgroundColor: color.withOpacity(0.14),
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
          subtitulo,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        value: valor,
        activeColor: AppColors.primary,
        onChanged: onChanged,
      ),
    );
  }

  Widget cardNotificacao(Map<String, dynamic> item) {
    final theme = Theme.of(context);

    final cor = item['cor'] as Color;
    final lida = item['lida'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lida
            ? theme.cardColor
            : Color.alphaBlend(
                AppColors.primary.withOpacity(
                  theme.brightness == Brightness.dark ? 0.10 : 0.05,
                ),
                theme.cardColor,
              ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: lida
              ? theme.colorScheme.outlineVariant.withOpacity(0.25)
              : AppColors.primary.withOpacity(0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              theme.brightness == Brightness.dark ? 0.16 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: cor.withOpacity(0.13),
            child: Icon(item['icone'] as IconData, color: cor),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['titulo'].toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  item['tempo'].toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  item['descricao'].toString(),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          if (!lida)
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final lista = notificacoesVisiveis;

    final naoLidas = lista.where((n) => n['lida'] != true).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Notificações'), centerTitle: true),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
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
                  'Escolha quais avisos deseja receber.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),

                const SizedBox(height: 22),

                opcao(
                  icon: Icons.inventory_2,
                  titulo: 'Novas entregas',
                  subtitulo: 'Avisar quando uma nova entrega for adicionada.',
                  valor: novasEntregas,
                  color: AppColors.primary,
                  onChanged: (valor) {
                    setState(() {
                      novasEntregas = valor;
                    });

                    salvar('notif_novas_entregas', valor);
                  },
                ),

                opcao(
                  icon: Icons.local_shipping,
                  titulo: 'Status das entregas',
                  subtitulo: 'Avisar sobre rota, conclusão e tentativas.',
                  valor: statusEntregas,
                  color: Colors.blue,
                  onChanged: (valor) {
                    setState(() {
                      statusEntregas = valor;
                    });

                    salvar('notif_status_entregas', valor);
                  },
                ),

                opcao(
                  icon: Icons.business,
                  titulo: 'Solicitações de vínculo',
                  subtitulo: 'Avisar quando uma empresa solicitar vínculo.',
                  valor: vinculos,
                  color: Colors.orange,
                  onChanged: (valor) {
                    setState(() {
                      vinculos = valor;
                    });

                    salvar('notif_vinculos', valor);
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
                  subtitulo: 'Reproduzir som ao receber notificações.',
                  valor: sons,
                  color: Colors.deepPurple,
                  onChanged: (valor) {
                    setState(() {
                      sons = valor;
                    });

                    salvar('notif_sons', valor);
                  },
                ),

                opcao(
                  icon: Icons.vibration,
                  titulo: 'Vibração',
                  subtitulo: 'Vibrar ao receber notificações.',
                  valor: vibracao,
                  color: AppColors.success,
                  onChanged: (valor) {
                    setState(() {
                      vibracao = valor;
                    });

                    salvar('notif_vibracao', valor);
                  },
                ),

                const SizedBox(height: 26),

                Text(
                  'Notificações recentes',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  '$naoLidas nova(s) notificação(ões)',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),

                const SizedBox(height: 16),

                if (lista.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withOpacity(
                          0.35,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),

                        const SizedBox(height: 10),

                        Text(
                          'Nenhuma notificação habilitada',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          'Ative alguma categoria acima para receber avisos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...lista.map(cardNotificacao),

                const SizedBox(height: 20),
              ],
            ),
    );
  }
}
