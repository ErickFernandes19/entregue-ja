import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
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
  bool _buscandoPreferencias = false;
  bool _marcandoNotificacao = false;
  bool _historicoCarregado = false;
  bool _sessaoInvalida = false;
  String? _autorizacaoSessao;
  bool ativandoNotificacoesWeb = false;
  bool notificacoesWebAtivadas = false;

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
    if (kIsWeb) {
      verificarPermissaoWeb();
    }
  }

  Future<Map<String, String>> _headersAutenticados() async {
    final headers = await EmpresaService.headersAutenticados();
    final autorizacao = headers['Authorization']?.trim() ?? '';
    if (_sessaoInvalida ||
        autorizacao.isEmpty ||
        (_autorizacaoSessao != null && _autorizacaoSessao != autorizacao)) {
      throw const ApiException(
        'Sua sessão expirou. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
    _autorizacaoSessao = autorizacao;
    return headers;
  }

  Future<void> _confirmarSessao(Map<String, String> headers) async {
    final atuais = await _headersAutenticados();
    if (atuais['Authorization'] != headers['Authorization']) {
      throw const ApiException(
        'Sua sessão foi alterada. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
  }

  void _validarResposta(http.Response resposta, List<int> aceitos) {
    if (!aceitos.contains(resposta.statusCode)) {
      throw ApiService.erroHttp(
        resposta.statusCode,
        utf8.decode(resposta.bodyBytes, allowMalformed: true),
      );
    }
  }

  void _tratarSessao(Object falha) {
    if (!mounted || falha is! ApiException || falha.statusCode != 401) return;
    setState(() {
      _sessaoInvalida = true;
      _preferenciasCarregadas = false;
      _preferenciasServidor = {};
      notificacoes = [];
      _historicoCarregado = false;
      totalNaoLidas = 0;
      erro = falha.mensagem;
      erroPreferencias = falha.mensagem;
    });
  }

  void _mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> verificarPermissaoWeb() async {
    try {
      final configuracao = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (!mounted || ativandoNotificacoesWeb) return;
      setState(() {
        notificacoesWebAtivadas =
            configuracao.authorizationStatus == AuthorizationStatus.authorized;
      });
    } catch (_) {
      if (!mounted || ativandoNotificacoesWeb) return;
      _mostrarMensagem('Não foi possível verificar a permissão do navegador.');
    }
  }

  Future<void> ativarNotificacoesWeb() async {
    if (!mounted || ativandoNotificacoesWeb || _sessaoInvalida) return;
    setState(() => ativandoNotificacoesWeb = true);

    try {
      final headers = await _headersAutenticados();
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

      await _confirmarSessao(headers);
      if (!mounted) return;
      await EmpresaService.registrarDispositivoFcmConfirmado();
      await _confirmarSessao(headers);
      if (!mounted) return;
      _mostrarMensagem(
        'Notificações ativadas e dispositivo registrado com sucesso.',
      );
    } catch (e) {
      if (!mounted) return;
      _tratarSessao(e);
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível ativar ou registrar as notificações. Tente novamente.',
        ),
      );
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
    final valores = {
      'empresa_entrega_concluida': entregaConcluida,
      'empresa_entrega_cancelada': entregaCancelada,
      'empresa_entrega_nao_realizada': entregaNaoRealizada,
      'empresa_novo_entregador': novoEntregador,
      'empresa_solicitacoes': solicitacoes,
      'empresa_sons': sons,
      'empresa_vibracao': vibracao,
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
    if (dados is! Map<String, dynamic>) {
      throw const FormatException('Resposta inválida');
    }
    const campos = [
      'entregaConcluida',
      'entregaCancelada',
      'entregaNaoRealizada',
      'novoEntregador',
      'solicitacoes',
      'novaEntrega',
      'vinculos',
      'sons',
      'vibracao',
    ];
    if (campos.any((campo) => dados[campo] is! bool)) {
      throw const FormatException('Preferências inválidas');
    }
    return dados;
  }

  void _aplicarPreferenciasServidor(Map<String, dynamic> preferencias) {
    _preferenciasServidor = Map<String, dynamic>.from(preferencias);
    entregaConcluida = preferencias['entregaConcluida'] == true;
    entregaCancelada = preferencias['entregaCancelada'] == true;
    entregaNaoRealizada = preferencias['entregaNaoRealizada'] == true;
    novoEntregador = preferencias['novoEntregador'] == true;
    solicitacoes =
        preferencias['solicitacoes'] == true &&
        preferencias['vinculos'] == true;
    sons = preferencias['sons'] == true;
    vibracao = preferencias['vibracao'] == true;
  }

  Future<void> _sincronizarPreferenciasLocais() async {
    try {
      await salvarPreferenciasLocais();
    } catch (_) {
      if (!mounted || _sessaoInvalida) return;
      setState(() {
        erroPreferencias =
            'As preferências do servidor foram confirmadas, mas não foi possível salvar todas no aparelho. Atualize para tentar novamente.';
      });
    }
  }

  Future<void> buscarPreferencias() async {
    if (!mounted ||
        _sessaoInvalida ||
        salvandoPreferencias ||
        _buscandoPreferencias) {
      return;
    }
    setState(() => _buscandoPreferencias = true);
    try {
      final headers = await _headersAutenticados();
      final response = await http
          .get(_urlPreferencias, headers: headers)
          .timeout(const Duration(seconds: 15));
      _validarResposta(response, [200]);
      final preferencias = _lerPreferencias(response);
      await _confirmarSessao(headers);
      if (!mounted) return;
      setState(() {
        _aplicarPreferenciasServidor(preferencias);
        _preferenciasCarregadas = true;
        erroPreferencias = null;
      });
      await _sincronizarPreferenciasLocais();
    } catch (e) {
      if (!mounted) return;
      _tratarSessao(e);
      setState(() {
        _preferenciasCarregadas = false;
        erroPreferencias = ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível sincronizar as preferências. Tente novamente.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _buscandoPreferencias = false);
      }
    }
  }

  Future<void> alterarPreferencia(String chave, bool valor) async {
    if (!mounted ||
        _sessaoInvalida ||
        !_preferenciasCarregadas ||
        salvandoPreferencias ||
        _buscandoPreferencias) {
      return;
    }

    final anterior = Map<String, dynamic>.from(_preferenciasServidor);
    final dados = Map<String, dynamic>.from(anterior);
    dados[chave] = valor;
    if (chave == 'solicitacoes') {
      dados['vinculos'] = valor;
    }
    setState(() {
      _aplicarPreferencia(chave, valor);
      salvandoPreferencias = true;
      erroPreferencias = null;
    });

    try {
      final headers = await _headersAutenticados();
      final response = await http
          .put(
            _urlPreferencias,
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode(dados),
          )
          .timeout(const Duration(seconds: 15));
      _validarResposta(response, [200]);
      final preferencias = _lerPreferencias(response);
      await _confirmarSessao(headers);
      if (!mounted) return;
      setState(() => _aplicarPreferenciasServidor(preferencias));
      await _sincronizarPreferenciasLocais();
    } catch (e) {
      if (!mounted) return;
      _tratarSessao(e);
      setState(() {
        if (!_sessaoInvalida) {
          _aplicarPreferenciasServidor(anterior);
        }
        _preferenciasCarregadas = false;
        final mensagem = ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível salvar a preferência.',
        );
        erroPreferencias = _sessaoInvalida
            ? mensagem
            : '$mensagem Atualize as preferências antes de alterar novamente.';
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
    if (!mounted || _sessaoInvalida || atualizando || _marcandoNotificacao) {
      return;
    }
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
      if (conteudo is! List ||
          conteudo.any((item) => item is! Map<String, dynamic>)) {
        throw const FormatException('Resposta inválida');
      }
      final lista = conteudo.cast<Map<String, dynamic>>().toList();
      final contagem = jsonDecode(utf8.decode(resultados[1].bodyBytes));
      if (contagem is! Map || contagem['quantidade'] is! num) {
        throw const FormatException('Contagem inválida');
      }
      final quantidade = contagem['quantidade'] as num;
      if (!quantidade.isFinite ||
          quantidade < 0 ||
          quantidade != quantidade.round()) {
        throw const FormatException('Contagem inválida');
      }
      await _confirmarSessao(headers);
      if (!mounted) return;
      setState(() {
        notificacoes = lista;
        _historicoCarregado = true;
        totalNaoLidas = quantidade.toInt();
        erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      _tratarSessao(e);
      setState(() {
        final mensagem = ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível atualizar as notificações.',
        );
        erro = _historicoCarregado
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
    if (!mounted ||
        _sessaoInvalida ||
        _lida(item) ||
        atualizando ||
        _marcandoNotificacao) {
      return;
    }
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null || id <= 0) {
      _mostrarMensagem(
        'Não foi possível identificar a notificação. Atualize a lista.',
      );
      return;
    }
    setState(() => _marcandoNotificacao = true);

    try {
      final headers = await _headersAutenticados();
      final response = await http
          .put(
            Uri.parse('${_urlNotificacoes.toString()}/$id/ler'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      _validarResposta(response, [200, 204]);
      await _confirmarSessao(headers);
      if (!mounted) return;
      setState(() {
        item['lida'] = true;
        if (totalNaoLidas > 0) {
          totalNaoLidas--;
        }
      });
    } catch (e) {
      if (!mounted) return;
      _tratarSessao(e);
      _mostrarMensagem(
        ApiService.mensagemErro(
          e,
          mensagemPadrao: 'Não foi possível marcar a notificação como lida.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _marcandoNotificacao = false);
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
            _preferenciasCarregadas &&
                !salvandoPreferencias &&
                !_buscandoPreferencias &&
                !_sessaoInvalida
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
      onTap: lida || atualizando || _marcandoNotificacao || _sessaoInvalida
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
            context.go('/empresa/inicio');
          },
        ),
        title: const Text('Notificações'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Atualizar notificações',
            onPressed: atualizando || _marcandoNotificacao || _sessaoInvalida
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
                        onPressed: _buscandoPreferencias || _sessaoInvalida
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
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed:
                                  ativandoNotificacoesWeb || _sessaoInvalida
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
                    _historicoCarregado
                        ? '$totalNaoLidas notificação(ões) não lida(s)'
                        : 'Contagem de notificações indisponível',
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
                            erro != null && !_historicoCarregado
                                ? 'Não foi possível carregar as notificações'
                                : 'Nenhuma notificação encontrada',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            erro != null && !_historicoCarregado
                                ? 'Atualize a lista para tentar novamente.'
                                : 'Quando houver novos avisos, eles aparecerão aqui.',
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
