import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/empresa_service.dart';
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
  bool entregaNaoRealizada = true;
  bool novoEntregador = true;
  bool solicitacoes = true;
  bool sons = true;
  bool vibracao = true;
  bool carregando = true;
  bool atualizando = false;
  bool salvandoPreferencias = false;

  int totalNaoLidas = 0;
  String? erro;
  String? erroPreferencias;

  List<Map<String, dynamic>> notificacoes = [];

  Map<String, dynamic> _preferenciasServidor = {};
  bool _preferenciasCarregadas = false;

  Uri get _urlNotificacoes {
    final base = ApiConfig.empresas;
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
        entregaConcluida = prefs.getBool('empresa_entrega_concluida') ?? true;
        entregaCancelada = prefs.getBool('empresa_entrega_cancelada') ?? true;
        entregaNaoRealizada =
            prefs.getBool('empresa_entrega_nao_realizada') ?? true;
        novoEntregador = prefs.getBool('empresa_novo_entregador') ?? true;
        solicitacoes = prefs.getBool('empresa_solicitacoes') ?? true;
        sons = prefs.getBool('empresa_sons') ?? true;
        vibracao = prefs.getBool('empresa_vibracao') ?? true;
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
      prefs.setBool('empresa_entrega_concluida', entregaConcluida),
      prefs.setBool('empresa_entrega_cancelada', entregaCancelada),
      prefs.setBool('empresa_entrega_nao_realizada', entregaNaoRealizada),
      prefs.setBool('empresa_novo_entregador', novoEntregador),
      prefs.setBool('empresa_solicitacoes', solicitacoes),
      prefs.setBool('empresa_sons', sons),
      prefs.setBool('empresa_vibracao', vibracao),
    ]);
  }

  Future<void> buscarPreferencias() async {
    try {
      final response = await http
          .get(
            _urlPreferencias,
            headers: await EmpresaService.headersAutenticados(),
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

      if (!mounted) return;

      setState(() {
        _preferenciasServidor = preferencias;
        _preferenciasCarregadas = true;

        entregaConcluida = preferencias['entregaConcluida'] == true;
        entregaCancelada = preferencias['entregaCancelada'] == true;
        entregaNaoRealizada = preferencias['entregaNaoRealizada'] == true;
        novoEntregador = preferencias['novoEntregador'] == true;
        solicitacoes =
            preferencias['solicitacoes'] == true &&
            preferencias['vinculos'] == true;
        sons = preferencias['sons'] == true;
        vibracao = preferencias['vibracao'] == true;

        erroPreferencias = null;
      });

      await salvarPreferenciasLocais();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _preferenciasCarregadas = false;
        erroPreferencias =
            'Não foi possível sincronizar as preferências com o servidor.';
      });
    }
  }

  Map<String, dynamic> get _dadosPreferencias {
    return {
      'entregaConcluida': entregaConcluida,
      'entregaCancelada': entregaCancelada,
      'entregaNaoRealizada': entregaNaoRealizada,
      'novoEntregador': novoEntregador,
      'solicitacoes': solicitacoes,
      'novaEntrega': _preferenciasServidor['novaEntrega'] ?? true,
      'vinculos': solicitacoes,
      'sons': sons,
      'vibracao': vibracao,
    };
  }

  Future<void> alterarPreferencia(String chave, bool valor) async {
    if (!_preferenciasCarregadas || salvandoPreferencias) {
      return;
    }

    final valoresAnteriores = Map<String, dynamic>.from(_dadosPreferencias);
    final solicitacoesAnteriores = solicitacoes;

    setState(() {
      _aplicarPreferencia(chave, valor);
      salvandoPreferencias = true;
      erroPreferencias = null;
    });

    try {
      final response = await http
          .put(
            _urlPreferencias,
            headers: {
              ...await EmpresaService.headersAutenticados(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(_dadosPreferencias),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final dados = jsonDecode(utf8.decode(response.bodyBytes));

      if (dados is! Map) {
        throw const FormatException('Resposta inválida');
      }

      if (!mounted) return;

      setState(() {
        _preferenciasServidor = Map<String, dynamic>.from(dados);
        solicitacoes =
            _preferenciasServidor['solicitacoes'] == true &&
            _preferenciasServidor['vinculos'] == true;
      });

      await salvarPreferenciasLocais();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        solicitacoes = solicitacoesAnteriores;
        for (final entry in valoresAnteriores.entries) {
          if (entry.value is bool) {
            _aplicarPreferencia(entry.key, entry.value as bool);
          }
        }

        erroPreferencias =
            'Não foi possível salvar a preferência. Tente novamente.';
      });
    } finally {
      if (mounted) {
        setState(() => salvandoPreferencias = false);
      }
    }
  }

  void _aplicarPreferencia(String chave, bool valor) {
    switch (chave) {
      case 'entregaConcluida':
        entregaConcluida = valor;
        break;
      case 'entregaCancelada':
        entregaCancelada = valor;
        break;
      case 'entregaNaoRealizada':
        entregaNaoRealizada = valor;
        break;
      case 'novoEntregador':
        novoEntregador = valor;
        break;
      case 'solicitacoes':
        solicitacoes = valor;
        break;
      case 'sons':
        sons = valor;
        break;
      case 'vibracao':
        vibracao = valor;
        break;
    }
  }

  Future<void> buscarNotificacoes() async {
    if (atualizando) return;

    if (mounted) {
      setState(() => atualizando = true);
    }

    try {
      final headers = await EmpresaService.headersAutenticados();

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

  bool _visivel(Map<String, dynamic> item) {
    final tipo = _tipo(item);

    if (tipo == 'ENTREGA_CONCLUIDA') {
      return entregaConcluida;
    }

    if (tipo == 'ENTREGA_NAO_REALIZADA') {
      return entregaNaoRealizada;
    }

    if (tipo == 'ENTREGA_CANCELADA') {
      return entregaCancelada;
    }

    if (tipo == 'VINCULO_ACEITO') {
      return novoEntregador;
    }

    if (tipo == 'VINCULO_RECUSADO' ||
        tipo == 'SOLICITACAO_VINCULO' ||
        tipo == 'SOLICITACAO_CANCELADA' ||
        tipo == 'CONVITE_VINCULO' ||
        tipo == 'VINCULO_PENDENTE' ||
        tipo == 'VINCULO_ENCERRADO') {
      return solicitacoes;
    }

    return true;
  }

  List<Map<String, dynamic>> get notificacoesVisiveis =>
      notificacoes.where(_visivel).toList();

  IconData _icone(String tipo) {
    if (tipo == 'ENTREGA_CONCLUIDA') {
      return Icons.check_circle;
    }

    if (tipo == 'ENTREGA_NAO_REALIZADA') {
      return Icons.warning_amber;
    }

    if (tipo == 'ENTREGA_CANCELADA') {
      return Icons.cancel;
    }

    if (tipo == 'VINCULO_ACEITO') {
      return Icons.person_add;
    }

    if (tipo.startsWith('VINCULO_')) {
      return Icons.pending_actions;
    }

    return Icons.notifications;
  }

  Color _cor(String tipo) {
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
            headers: await EmpresaService.headersAutenticados(),
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
        onChanged: _preferenciasCarregadas && !salvandoPreferencias
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
                    'Escolha quais avisos sua empresa deseja receber.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (erroPreferencias != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      erroPreferencias!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    if (!_preferenciasCarregadas)
                      TextButton.icon(
                        onPressed: buscarPreferencias,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                  ],
                  const SizedBox(height: 22),
                  opcao(
                    icon: Icons.check_circle,
                    titulo: 'Entrega concluída',
                    subtitulo: 'Receber aviso quando uma entrega for concluída',
                    valor: entregaConcluida,
                    color: AppColors.primary,
                    onChanged: (v) => alterarPreferencia('entregaConcluida', v),
                  ),
                  opcao(
                    icon: Icons.cancel,
                    titulo: 'Entrega cancelada',
                    subtitulo: 'Receber aviso quando uma entrega for cancelada',
                    valor: entregaCancelada,
                    color: AppColors.primary,
                    onChanged: (v) => alterarPreferencia('entregaCancelada', v),
                  ),
                  opcao(
                    icon: Icons.warning_amber,
                    titulo: 'Entrega não realizada',
                    subtitulo:
                        'Receber aviso quando uma entrega não for realizada',
                    valor: entregaNaoRealizada,
                    color: Colors.orange,
                    onChanged: (v) =>
                        alterarPreferencia('entregaNaoRealizada', v),
                  ),
                  opcao(
                    icon: Icons.person_add,
                    titulo: 'Novo entregador vinculado',
                    subtitulo:
                        'Receber aviso quando um entregador aceitar o vínculo',
                    valor: novoEntregador,
                    color: AppColors.primary,
                    onChanged: (v) => alterarPreferencia('novoEntregador', v),
                  ),
                  opcao(
                    icon: Icons.pending_actions,
                    titulo: 'Solicitações e vínculos',
                    subtitulo: 'Receber avisos sobre solicitações e vínculos',
                    valor: solicitacoes,
                    color: AppColors.primary,
                    onChanged: (v) => alterarPreferencia('solicitacoes', v),
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
                    color: Colors.deepPurple,
                    onChanged: (v) => alterarPreferencia('sons', v),
                  ),
                  opcao(
                    icon: Icons.vibration,
                    titulo: 'Vibração',
                    subtitulo: 'Vibrar ao receber notificações',
                    valor: vibracao,
                    color: AppColors.success,
                    onChanged: (v) => alterarPreferencia('vibracao', v),
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
