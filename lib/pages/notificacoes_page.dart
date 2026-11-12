import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/auth_service.dart';
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
  bool atualizando = false;
  bool salvandoPreferencias = false;
  bool preferenciasCarregadas = false;

  int totalNaoLidas = 0;
  String? erro;
  String? erroPreferencias;

  List<Map<String, dynamic>> notificacoes = [];
  Map<String, dynamic> preferenciasServidor = {};

  Uri get _urlNotificacoes {
    final base = ApiConfig.auth;
    final indice = base.lastIndexOf('/');
    final origem = indice >= 0 ? base.substring(0, indice) : base;
    return Uri.parse('$origem/notificacoes');
  }

  Uri get _urlPreferencias =>
      Uri.parse('${_urlNotificacoes.toString()}/preferencias');

  Uri get _urlNaoLidas => Uri.parse('${_urlNotificacoes.toString()}/nao-lidas');

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    try {
      await carregarPreferenciasLocais();

      await Future.wait([buscarPreferencias(), buscarNotificacoes()]);
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  Future<void> carregarPreferenciasLocais() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      setState(() {
        novasEntregas = prefs.getBool('notif_novas_entregas') ?? true;
        statusEntregas = prefs.getBool('notif_status_entregas') ?? true;
        vinculos = prefs.getBool('notif_vinculos') ?? true;
        sons = prefs.getBool('notif_sons') ?? true;
        vibracao = prefs.getBool('notif_vibracao') ?? true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        erroPreferencias = 'Não foi possível carregar as preferências locais.';
      });
    }
  }

  Future<void> salvarPreferenciasLocais() async {
    final prefs = await SharedPreferences.getInstance();

    await Future.wait([
      prefs.setBool('notif_novas_entregas', novasEntregas),
      prefs.setBool('notif_status_entregas', statusEntregas),
      prefs.setBool('notif_vinculos', vinculos),
      prefs.setBool('notif_sons', sons),
      prefs.setBool('notif_vibracao', vibracao),
    ]);
  }

  Future<void> buscarPreferencias() async {
    if (salvandoPreferencias) return;

    try {
      final response = await http
          .get(
            _urlPreferencias,
            headers: await AuthService.headersAutenticados(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final dados = jsonDecode(utf8.decode(response.bodyBytes));

      if (dados is! Map) {
        throw const FormatException('Resposta inválida');
      }

      final preferencias = Map<String, dynamic>.from(dados);

      const campos = [
        'novaEntrega',
        'entregaConcluida',
        'entregaCancelada',
        'entregaNaoRealizada',
        'vinculos',
        'sons',
        'vibracao',
      ];

      if (campos.any((campo) => preferencias[campo] is! bool)) {
        throw const FormatException('Preferências inválidas');
      }

      if (!mounted || salvandoPreferencias) return;

      setState(() {
        preferenciasServidor = preferencias;
        preferenciasCarregadas = true;

        novasEntregas = preferencias['novaEntrega'] == true;

        statusEntregas =
            preferencias['entregaConcluida'] == true &&
            preferencias['entregaCancelada'] == true &&
            preferencias['entregaNaoRealizada'] == true;

        vinculos = preferencias['vinculos'] == true;
        sons = preferencias['sons'] == true;
        vibracao = preferencias['vibracao'] == true;

        erroPreferencias = null;
      });

      await salvarPreferenciasLocais();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        if (!preferenciasCarregadas) {
          preferenciasCarregadas = false;
        }

        erroPreferencias =
            'Não foi possível sincronizar as preferências com o servidor.';
      });
    }
  }

  Map<String, dynamic> get dadosPreferencias {
    return {
      'entregaConcluida': preferenciasServidor['entregaConcluida'] ?? true,
      'entregaCancelada': preferenciasServidor['entregaCancelada'] ?? true,
      'entregaNaoRealizada':
          preferenciasServidor['entregaNaoRealizada'] ?? true,
      'novoEntregador': preferenciasServidor['novoEntregador'] ?? true,
      'solicitacoes': preferenciasServidor['solicitacoes'] ?? true,
      'novaEntrega': novasEntregas,
      'vinculos': vinculos,
      'sons': sons,
      'vibracao': vibracao,
    };
  }

  void aplicarPreferencia(String chave, bool valor) {
    switch (chave) {
      case 'novaEntrega':
        novasEntregas = valor;
        break;
      case 'statusEntregas':
        statusEntregas = valor;
        break;
      case 'vinculos':
        vinculos = valor;
        break;
      case 'sons':
        sons = valor;
        break;
      case 'vibracao':
        vibracao = valor;
        break;
    }
  }

  Future<void> alterarPreferencia(String chave, bool valor) async {
    if (!preferenciasCarregadas || salvandoPreferencias) {
      return;
    }

    final anterior = Map<String, dynamic>.from(preferenciasServidor);

    setState(() {
      aplicarPreferencia(chave, valor);
      salvandoPreferencias = true;
      erroPreferencias = null;
    });

    try {
      final dados = dadosPreferencias;

      if (chave == 'statusEntregas') {
        dados['entregaConcluida'] = valor;
        dados['entregaCancelada'] = valor;
        dados['entregaNaoRealizada'] = valor;
      }

      final response = await http
          .put(
            _urlPreferencias,
            headers: {
              ...await AuthService.headersAutenticados(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(dados),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final resposta = jsonDecode(utf8.decode(response.bodyBytes));

      if (resposta is! Map) {
        throw const FormatException('Resposta inválida');
      }

      if (!mounted) return;

      setState(() {
        preferenciasServidor = Map<String, dynamic>.from(resposta);
        novasEntregas = preferenciasServidor['novaEntrega'] == true;
        statusEntregas =
            preferenciasServidor['entregaConcluida'] == true &&
            preferenciasServidor['entregaCancelada'] == true &&
            preferenciasServidor['entregaNaoRealizada'] == true;
        vinculos = preferenciasServidor['vinculos'] == true;
        sons = preferenciasServidor['sons'] == true;
        vibracao = preferenciasServidor['vibracao'] == true;
      });

      await salvarPreferenciasLocais();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        preferenciasServidor = anterior;
        novasEntregas = anterior['novaEntrega'] == true;
        statusEntregas =
            anterior['entregaConcluida'] == true &&
            anterior['entregaCancelada'] == true &&
            anterior['entregaNaoRealizada'] == true;
        vinculos = anterior['vinculos'] == true;
        sons = anterior['sons'] == true;
        vibracao = anterior['vibracao'] == true;

        erroPreferencias =
            'Não foi possível salvar a preferência. Tente novamente.';
      });
    } finally {
      if (mounted) {
        setState(() => salvandoPreferencias = false);
      }
    }
  }

  Future<void> buscarNotificacoes() async {
    if (atualizando) return;

    if (mounted) {
      setState(() => atualizando = true);
    }

    try {
      final headers = await AuthService.headersAutenticados();

      final resultados = await Future.wait([
        http
            .get(
              _urlNotificacoes.replace(
                queryParameters: {'pagina': '0', 'tamanho': '50'},
              ),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
        http
            .get(_urlNaoLidas, headers: headers)
            .timeout(const Duration(seconds: 15)),
      ]);

      if (resultados[0].statusCode != 200 || resultados[1].statusCode != 200) {
        throw Exception('Erro ao buscar notificações');
      }

      final dados = jsonDecode(utf8.decode(resultados[0].bodyBytes));

      final dynamic conteudo = dados is Map ? dados['content'] : dados;

      if (conteudo is! List) {
        throw const FormatException('Resposta inválida');
      }

      final lista = conteudo
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final contagem = jsonDecode(utf8.decode(resultados[1].bodyBytes));

      if (contagem is! Map || contagem['quantidade'] is! num) {
        throw const FormatException('Contagem inválida');
      }

      if (!mounted) return;

      setState(() {
        notificacoes = lista;
        totalNaoLidas = (contagem['quantidade'] as num).toInt();
        erro = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        erro = 'Não foi possível atualizar as notificações.';
      });
    } finally {
      if (mounted) {
        setState(() => atualizando = false);
      }
    }
  }

  String _tipo(Map<String, dynamic> item) =>
      (item['tipo'] ?? '').toString().toUpperCase();

  bool _lida(Map<String, dynamic> item) => item['lida'] == true;

  List<Map<String, dynamic>> get notificacoesVisiveis => notificacoes;

  IconData _icone(String tipo) {
    if (tipo == 'NOVA_ENTREGA' || tipo == 'ENTREGA_ATRIBUIDA') {
      return Icons.inventory_2;
    }

    if (tipo.startsWith('VINCULO_') ||
        tipo == 'SOLICITACAO_VINCULO' ||
        tipo == 'CONVITE_VINCULO') {
      return Icons.business;
    }

    if (tipo == 'ENTREGA_CONCLUIDA') {
      return Icons.check_circle;
    }

    if (tipo == 'ENTREGA_CANCELADA') {
      return Icons.cancel_outlined;
    }

    if (tipo == 'ENTREGA_NAO_REALIZADA') {
      return Icons.warning_amber;
    }

    return Icons.local_shipping;
  }

  Color _cor(String tipo) {
    if (tipo.startsWith('VINCULO_') ||
        tipo == 'SOLICITACAO_VINCULO' ||
        tipo == 'CONVITE_VINCULO') {
      return Colors.orange;
    }

    if (tipo == 'ENTREGA_CONCLUIDA') {
      return AppColors.success;
    }

    if (tipo == 'ENTREGA_CANCELADA') {
      return Colors.redAccent;
    }

    if (tipo == 'ENTREGA_NAO_REALIZADA') {
      return Colors.orange;
    }

    return AppColors.primary;
  }

  String _tempo(Map<String, dynamic> item) {
    final valor =
        item['criadaEm'] ??
        item['criadoEm'] ??
        item['dataCriacao'] ??
        item['createdAt'] ??
        item['dataHora'];

    if (valor == null) return '';

    final data = DateTime.tryParse(valor.toString());

    if (data == null) return '';

    final local = data.toLocal();
    final agora = DateTime.now();
    final diferenca = agora.difference(local);

    if (!diferenca.isNegative && diferenca.inMinutes < 1) {
      return 'Agora mesmo';
    }

    if (!diferenca.isNegative && diferenca.inMinutes < 60) {
      return '${diferenca.inMinutes} min atrás';
    }

    if (!diferenca.isNegative && diferenca.inHours < 24) {
      return '${diferenca.inHours} h atrás';
    }

    final dia = local.day.toString().padLeft(2, '0');
    final mes = local.month.toString().padLeft(2, '0');
    final hora = local.hour.toString().padLeft(2, '0');
    final minuto = local.minute.toString().padLeft(2, '0');

    return '$dia/$mes/${local.year} às $hora:$minuto';
  }

  Future<void> marcarComoLida(Map<String, dynamic> item) async {
    if (_lida(item)) return;

    final id = item['id'];

    if (id == null) return;

    try {
      final response = await http
          .put(
            Uri.parse('${_urlNotificacoes.toString()}/$id/ler'),
            headers: await AuthService.headersAutenticados(),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      if (!mounted) return;

      setState(() {
        item['lida'] = true;

        if (totalNaoLidas > 0) {
          totalNaoLidas--;
        }
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível marcar a notificação como lida.'),
        ),
      );
    }
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
        onChanged: preferenciasCarregadas && !salvandoPreferencias
            ? onChanged
            : null,
      ),
    );
  }

  Widget cardNotificacao(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final tipo = _tipo(item);
    final cor = _cor(tipo);
    final lida = _lida(item);
    final tempo = _tempo(item);

    return InkWell(
      onTap: lida ? null : () => marcarComoLida(item),
      borderRadius: BorderRadius.circular(22),
      child: Container(
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
              child: Icon(_icone(tipo), color: cor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (item['titulo'] ?? 'Notificação').toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (tempo.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      tempo,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    (item['mensagem'] ?? item['descricao'] ?? '').toString(),
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!lida)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: CircleAvatar(
                  radius: 4.5,
                  backgroundColor: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lista = notificacoesVisiveis;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Atualizar notificações',
            onPressed: atualizando ? null : buscarNotificacoes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  buscarNotificacoes(),
                  if (!salvandoPreferencias) buscarPreferencias(),
                ]);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                  if (erroPreferencias != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      erroPreferencias!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    if (!preferenciasCarregadas)
                      TextButton.icon(
                        onPressed: buscarPreferencias,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                  ],
                  const SizedBox(height: 22),
                  opcao(
                    icon: Icons.inventory_2,
                    titulo: 'Novas entregas',
                    subtitulo: 'Avisar quando uma nova entrega for adicionada.',
                    valor: novasEntregas,
                    color: AppColors.primary,
                    onChanged: (valor) =>
                        alterarPreferencia('novaEntrega', valor),
                  ),
                  opcao(
                    icon: Icons.local_shipping,
                    titulo: 'Status das entregas',
                    subtitulo: 'Avisar sobre rota, conclusão e tentativas.',
                    valor: statusEntregas,
                    color: Colors.blue,
                    onChanged: (valor) =>
                        alterarPreferencia('statusEntregas', valor),
                  ),
                  opcao(
                    icon: Icons.business,
                    titulo: 'Solicitações de vínculo',
                    subtitulo: 'Avisar quando uma empresa solicitar vínculo.',
                    valor: vinculos,
                    color: Colors.orange,
                    onChanged: (valor) => alterarPreferencia('vinculos', valor),
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
                    onChanged: (valor) => alterarPreferencia('sons', valor),
                  ),
                  opcao(
                    icon: Icons.vibration,
                    titulo: 'Vibração',
                    subtitulo: 'Vibrar ao receber notificações.',
                    valor: vibracao,
                    color: AppColors.success,
                    onChanged: (valor) => alterarPreferencia('vibracao', valor),
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
                    '$totalNaoLidas notificação(ões) não lida(s)',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  if (erro != null) ...[
                    Text(
                      erro!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],
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
                            Icons.notifications_none,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhuma notificação encontrada',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Quando houver novos avisos, eles aparecerão aqui.',
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
            ),
    );
  }
}
