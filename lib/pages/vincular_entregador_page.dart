import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class VincularEntregadorPage extends StatefulWidget {
  const VincularEntregadorPage({super.key});

  @override
  State<VincularEntregadorPage> createState() => _VincularEntregadorPageState();
}

class _VincularEntregadorPageState extends State<VincularEntregadorPage> {
  final emailController = TextEditingController();

  bool carregando = false;
  bool carregandoPendentes = true;
  bool _consultandoPendentes = false;
  bool _cancelandoSolicitacao = false;
  String? _erroPendentes;
  String? _empresaDaTela;

  bool get _operacaoEmAndamento => carregando || _cancelandoSolicitacao;

  List<dynamic> pendentes = [];

  @override
  void initState() {
    super.initState();
    carregarPendentes();
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? AppColors.error : null,
      ),
    );
  }

  Future<String> _validarSessao() async {
    final empresa = await EmpresaService.empresaLogada();
    if (empresa == null || empresa.trim().isEmpty) {
      throw const ApiException(
        'Sua sessão expirou. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }
    if (_empresaDaTela != null && _empresaDaTela != empresa) {
      throw const ApiException(
        'Sua sessão mudou. Abra esta tela novamente.',
        statusCode: 401,
      );
    }
    _empresaDaTela = empresa;
    return empresa;
  }

  void _tratarFalha(
    Object erro,
    String mensagemPadrao, {
    bool consulta = false,
  }) {
    if (!mounted) return;
    final mensagem = ApiService.mensagemErro(
      erro,
      mensagemPadrao: mensagemPadrao,
    );
    final semAcesso =
        erro is ApiException &&
        (erro.statusCode == 401 || (consulta && erro.statusCode == 403));
    if (consulta || semAcesso) {
      setState(() {
        if (semAcesso) {
          pendentes = [];
        }
        _erroPendentes = mensagem;
      });
    }
    _mostrarMensagem(
      consulta && pendentes.isNotEmpty
          ? '$mensagem Exibindo as últimas solicitações disponíveis.'
          : mensagem,
      erro: true,
    );
  }

  Future<void> carregarPendentes({bool aposOperacao = false}) async {
    if (!mounted ||
        _consultandoPendentes ||
        (_operacaoEmAndamento && !aposOperacao)) {
      return;
    }
    setState(() => _consultandoPendentes = true);
    try {
      await _validarSessao();
      if (!mounted) return;
      final resultado = await EmpresaService.buscarEntregadoresPendentes(
        lancarErro: true,
      );
      if (!mounted) return;
      await _validarSessao();
      if (!mounted) return;

      final lista = <Map<String, dynamic>>[];
      for (final item in resultado) {
        if (item is! Map) {
          throw const FormatException('Solicitação inválida.');
        }
        final dados = Map<String, dynamic>.from(item);
        final email = dados['email']?.toString().trim() ?? '';
        if (email.isEmpty) {
          throw const FormatException('E-mail do entregador ausente.');
        }
        lista.add(dados);
      }
      setState(() {
        pendentes = lista;
        _erroPendentes = null;
      });
    } catch (e) {
      _tratarFalha(
        e,
        'Não foi possível carregar as solicitações pendentes. Tente novamente.',
        consulta: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _consultandoPendentes = false;
          carregandoPendentes = false;
        });
      }
    }
  }

  Future<void> cancelarSolicitacao(String entregadorEmail) async {
    if (!mounted || _operacaoEmAndamento || _consultandoPendentes) return;
    final email = entregadorEmail.trim();
    if (email.isEmpty) {
      _mostrarMensagem('E-mail do entregador não disponível.', erro: true);
      return;
    }
    setState(() => _cancelandoSolicitacao = true);
    try {
      await _validarSessao();
      if (!mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Cancelar solicitação'),
            content: const Text(
              'Deseja realmente cancelar a solicitação de vínculo com este entregador?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },
                child: const Text('Voltar'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                icon: const Icon(Icons.close),
                label: const Text('Cancelar solicitação'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      );

      if (!mounted || confirmar != true) return;
      await _validarSessao();
      if (!mounted) return;

      final sucesso = await EmpresaService.cancelarSolicitacaoVinculo(
        email,
        lancarErro: true,
      );
      if (!mounted) return;
      await _validarSessao();
      if (!mounted) return;
      if (!sucesso) {
        throw const ApiException('Não foi possível cancelar a solicitação.');
      }
      setState(() {
        pendentes = pendentes.where((item) {
          return item['email']?.toString().trim().toLowerCase() !=
              email.toLowerCase();
        }).toList();
      });
      _mostrarMensagem('Solicitação cancelada com sucesso');
      await carregarPendentes(aposOperacao: true);
    } catch (e) {
      _tratarFalha(
        e,
        'Não foi possível cancelar a solicitação. Tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => _cancelandoSolicitacao = false);
      }
    }
  }

  Future<void> vincularEntregador() async {
    if (!mounted || _operacaoEmAndamento || _consultandoPendentes) return;
    FocusScope.of(context).unfocus();
    final entregadorEmail = emailController.text.trim().toLowerCase();
    if (entregadorEmail.isEmpty) {
      _mostrarMensagem('Digite o e-mail do entregador', erro: true);
      return;
    }
    if (entregadorEmail.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(entregadorEmail)) {
      _mostrarMensagem('Informe um e-mail válido.', erro: true);
      return;
    }

    setState(() => carregando = true);
    try {
      await _validarSessao();
      if (!mounted) return;
      final sucesso = await EmpresaService.vincularEntregador(
        entregadorEmail,
        lancarErro: true,
      );
      if (!mounted) return;
      await _validarSessao();
      if (!mounted) return;
      if (!sucesso) {
        throw const ApiException('Não foi possível enviar a solicitação.');
      }
      _mostrarMensagem('Solicitação enviada ao entregador');
      emailController.clear();
      await carregarPendentes(aposOperacao: true);
    } catch (e) {
      _tratarFalha(
        e,
        'Não foi possível enviar a solicitação. Tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  Widget cardPendente(Map<String, dynamic> entregador) {
    final theme = Theme.of(context);

    final nome = entregador['nome']?.toString() ?? 'Entregador';
    final email = entregador['email']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.16 : 0.04,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: AppColors.warning.withValues(alpha: 0.14),
                child: const Icon(Icons.schedule, color: AppColors.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        email,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Aguardando resposta',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  email.isEmpty || _operacaoEmAndamento || _consultandoPendentes
                  ? null
                  : () async {
                      await cancelarSolicitacao(email);
                    },
              icon: const Icon(Icons.close),
              label: const Text('Cancelar solicitação'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar ao início',
          icon: const Icon(Icons.arrow_back),
          onPressed: _operacaoEmAndamento
              ? null
              : () {
                  context.go('/empresa/inicio');
                },
        ),
        title: const Text('Vincular Entregador'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: carregarPendentes,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enviar solicitação',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Informe o e-mail do entregador que deseja vincular à empresa.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enabled: !_operacaoEmAndamento,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    onSubmitted: (_) => vincularEntregador(),
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: const InputDecoration(
                      labelText: 'E-mail do entregador',
                      hintText: 'exemplo@email.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _operacaoEmAndamento || _consultandoPendentes
                          ? null
                          : vincularEntregador,
                      icon: carregando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.person_add),
                      label: Text(
                        carregando ? 'Enviando...' : 'Enviar solicitação',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Vínculos pendentes',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (pendentes.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      pendentes.length.toString(),
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (carregandoPendentes)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (pendentes.isEmpty)
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
                      Icons.person_search_outlined,
                      size: 46,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _erroPendentes == null
                          ? 'Nenhum vínculo pendente'
                          : 'Não foi possível carregar os vínculos',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _erroPendentes == null
                          ? 'As solicitações enviadas aparecerão aqui.'
                          : '$_erroPendentes Puxe para baixo para atualizar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...pendentes.map(
                (item) => cardPendente(Map<String, dynamic>.from(item)),
              ),
          ],
        ),
      ),
    );
  }
}
