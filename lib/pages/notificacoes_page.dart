import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
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
  bool buscandoPreferencias = false;
  bool marcandoNotificacao = false;
  bool historicoCarregado = false;
  bool preferenciasCarregadas = false;
  bool ativandoNotificacoesWeb = false;
  bool notificacoesWebAtivadas = false;

  int totalNaoLidas = 0;
  String? erro;
  String? erroPreferencias;
  String? erroPermissaoWeb;

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

  Future<Map<String, String>> _headersAutenticados() async {
    final headers = await AuthService.headersAutenticados();
    if ((headers['Authorization'] ?? '').trim().isEmpty) {
      throw const ApiException(
        'Sua sessão expirou. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
    return headers;
  }

  void _validarResposta(http.Response resposta, List<int> statusAceitos) {
    if (!statusAceitos.contains(resposta.statusCode)) {
      throw ApiService.erroHttp(
        resposta.statusCode,
        utf8.decode(resposta.bodyBytes, allowMalformed: true),
      );
    }
  }

  void _mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  void initState() {
    super.initState();
    carregar();
    if (kIsWeb) {
      verificarPermissaoWeb();
    }
  }

  Future<void> verificarPermissaoWeb() async {
    try {
      final configuracao = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (!mounted || ativandoNotificacoesWeb) return;
      setState(() {
        notificacoesWebAtivadas =
            configuracao.authorizationStatus == AuthorizationStatus.authorized;
        erroPermissaoWeb = null;
      });
    } catch (_) {
      if (!mounted || ativandoNotificacoesWeb) return;
      setState(() {
        erroPermissaoWeb =
            'Não foi possível verificar a permissão do navegador.';
      });
    }
  }

  Future<void> ativarNotificacoesWeb() async {
    if (!mounted || ativandoNotificacoesWeb) return;
    setState(() {
      ativandoNotificacoesWeb = true;
      erroPermissaoWeb = null;
    });

    try {
      final permissao = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (!mounted) return;
      final autorizada =
          permissao.authorizationStatus == AuthorizationStatus.authorized;
      setState(() => notificacoesWebAtivadas = autorizada);
      if (!autorizada) {
        _mostrarMensagem(
          'Autorize as notificações nas configurações do navegador.',
        );
        return;
      }

      await _headersAutenticados();
      await AuthService.registrarDispositivoFcmConfirmado();
      if (!mounted) return;
      _mostrarMensagem(
        'Notificações ativadas e dispositivo registrado com sucesso.',
      );
    } catch (e) {
      if (!mounted) return;
      final mensagem = ApiService.mensagemErro(
        e,
        mensagemPadrao:
            'Não foi possível ativar ou registrar as notificações. Tente novamente.',
      );
      setState(() => erroPermissaoWeb = mensagem);
      _mostrarMensagem(mensagem);
    } finally {
      if (mounted) {
        setState(() => ativandoNotificacoesWeb = false);
      }
    }
  }

  Future<void> carregar() async {
    try {
      await carregarPreferenciasLocais();
      if (!mounted) return;

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
    final valores = {
      'notif_novas_entregas': novasEntregas,
      'notif_status_entregas': statusEntregas,
      'notif_vinculos': vinculos,
      'notif_sons': sons,
      'notif_vibracao': vibracao,
    };
    final prefs = await SharedPreferences.getInstance();
    final resultados = await Future.wait(
      valores.entries.map((item) => prefs.setBool(item.key, item.value)),
    );
    if (resultados.any((sucesso) => !sucesso)) {
      throw const ApiException(
        'Não foi possível salvar todas as preferências no aparelho.',
      );
    }
  }

  Map<String, dynamic> _lerPreferencias(http.Response response) {
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
    return preferencias;
  }

  void _aplicarPreferenciasServidor(Map<String, dynamic> preferencias) {
    preferenciasServidor = preferencias;
    novasEntregas = preferencias['novaEntrega'] == true;
    statusEntregas =
        preferencias['entregaConcluida'] == true &&
        preferencias['entregaCancelada'] == true &&
        preferencias['entregaNaoRealizada'] == true;
    vinculos = preferencias['vinculos'] == true;
    sons = preferencias['sons'] == true;
    vibracao = preferencias['vibracao'] == true;
  }

  Future<void> _sincronizarPreferenciasLocais() async {
    try {
      await salvarPreferenciasLocais();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        erroPreferencias =
            'As preferências do servidor foram carregadas, mas não foi possível salvar todas no aparelho. Atualize para tentar novamente.';
      });
    }
  }

  Future<void> buscarPreferencias() async {
    if (!mounted || salvandoPreferencias || buscandoPreferencias) return;
    setState(() => buscandoPreferencias = true);

    try {
      final response = await http
          .get(_urlPreferencias, headers: await _headersAutenticados())
          .timeout(const Duration(seconds: 15));
      _validarResposta(response, [200]);
      final preferencias = _lerPreferencias(response);
      if (!mounted) return;
      setState(() {
        _aplicarPreferenciasServidor(preferencias);
        preferenciasCarregadas = true;
        erroPreferencias = null;
      });
      await _sincronizarPreferenciasLocais();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        preferenciasCarregadas = false;
        erroPreferencias = ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível sincronizar as preferências. Tente novamente.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => buscandoPreferencias = false);
      }
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
    if (!mounted ||
        !preferenciasCarregadas ||
        salvandoPreferencias ||
        buscandoPreferencias) {
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
            headers: await _headersAutenticados(),
            body: jsonEncode(dados),
          )
          .timeout(const Duration(seconds: 15));
      _validarResposta(response, [200]);
      final preferencias = _lerPreferencias(response);
      if (!mounted) return;
      setState(() => _aplicarPreferenciasServidor(preferencias));
      await _sincronizarPreferenciasLocais();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aplicarPreferenciasServidor(anterior);
        preferenciasCarregadas = false;
        final mensagem = ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível salvar a preferência.',
        );
        erroPreferencias =
            '$mensagem Atualize as preferências antes de alterar novamente.';
      });
    } finally {
      if (mounted) {
        setState(() => salvandoPreferencias = false);
      }
    }
  }

  Future<void> buscarNotificacoes() async {
    if (!mounted || atualizando || marcandoNotificacao) return;
    setState(() => atualizando = true);

    try {
      final headers = await _headersAutenticados();

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

      for (final resposta in resultados) {
        _validarResposta(resposta, [200]);
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
        historicoCarregado = true;
        totalNaoLidas = (contagem['quantidade'] as num).toInt();
        erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final mensagem = ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível atualizar as notificações.',
        );
        erro = historicoCarregado
            ? '$mensagem Exibindo a última atualização.'
            : mensagem;
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

    final texto = valor.toString().trim();
    if (texto.isEmpty) return '';

    final possuiFuso = RegExp(r'(?:[zZ]|[+-]\d{2}:?\d{2})$').hasMatch(texto);
    final data = DateTime.tryParse(possuiFuso ? texto : '${texto}Z');

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
    if (!mounted || _lida(item) || atualizando || marcandoNotificacao) return;
    final id = item['id'];
    if (id == null) {
      _mostrarMensagem(
        'Não foi possível identificar a notificação. Atualize a lista.',
      );
      return;
    }
    setState(() => marcandoNotificacao = true);

    try {
      final response = await http
          .put(
            Uri.parse('${_urlNotificacoes.toString()}/$id/ler'),
            headers: await _headersAutenticados(),
          )
          .timeout(const Duration(seconds: 15));
      _validarResposta(response, [200, 204]);
      if (!mounted) return;
      setState(() {
        item['lida'] = true;
        if (totalNaoLidas > 0) {
          totalNaoLidas--;
        }
      });
    } catch (e) {
      if (!mounted) return;
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível marcar a notificação como lida.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => marcandoNotificacao = false);
      }
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
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.16 : 0.05,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        secondary: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
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
        activeThumbColor: AppColors.primary,
        onChanged:
            preferenciasCarregadas &&
                !salvandoPreferencias &&
                !buscandoPreferencias
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
      onTap: lida || atualizando || marcandoNotificacao
          ? null
          : () => marcarComoLida(item),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: lida
              ? theme.cardColor
              : Color.alphaBlend(
                  AppColors.primary.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.10 : 0.05,
                  ),
                  theme.cardColor,
                ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: lida
                ? theme.colorScheme.outlineVariant.withValues(alpha: 0.25)
                : AppColors.primary.withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.16 : 0.05,
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
              backgroundColor: cor.withValues(alpha: 0.13),
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
        leading: IconButton(
          tooltip: 'Voltar ao início',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.go('/entregador/inicio');
          },
        ),
        title: const Text('Notificações'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Atualizar notificações',
            onPressed: carregando || atualizando || marcandoNotificacao
                ? null
                : buscarNotificacoes,
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
                    TextButton.icon(
                      onPressed: buscandoPreferencias || salvandoPreferencias
                          ? null
                          : buscarPreferencias,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                  if (kIsWeb) ...[
                    const SizedBox(height: 18),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notificações do navegador',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              notificacoesWebAtivadas
                                  ? 'O navegador permite notificações. Você pode atualizar o registro deste dispositivo.'
                                  : 'Ative a permissão para receber avisos mesmo quando esta aba não estiver em primeiro plano.',
                            ),
                            if (erroPermissaoWeb != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                erroPermissaoWeb!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: ativandoNotificacoesWeb
                                  ? null
                                  : ativarNotificacoesWeb,
                              icon: ativandoNotificacoesWeb
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.notifications_active_outlined,
                                    ),
                              label: Text(
                                notificacoesWebAtivadas
                                    ? 'Atualizar registro'
                                    : 'Ativar notificações',
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    historicoCarregado
                        ? '$totalNaoLidas notificação(ões) não lida(s)'
                        : 'Contagem indisponível',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  if (erro != null) ...[
                    Text(
                      erro!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    TextButton.icon(
                      onPressed: atualizando || marcandoNotificacao
                          ? null
                          : buscarNotificacoes,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (lista.isEmpty && historicoCarregado)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
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
