import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/empresa_lista_entregas_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class EmpresaEntregasPage extends StatefulWidget {
  final String? entregadorEmail;
  final String? entregadorNome;

  const EmpresaEntregasPage({
    super.key,
    this.entregadorEmail,
    this.entregadorNome,
  });

  @override
  State<EmpresaEntregasPage> createState() => _EmpresaEntregasPageState();
}

class _EmpresaEntregasPageState extends State<EmpresaEntregasPage> {
  final pesquisaController = TextEditingController();

  List<dynamic> entregas = [];
  String filtro = 'em_rota';
  bool carregando = true;
  bool _consultandoEntregas = false;
  bool _abrindoDetalhes = false;
  bool _dadosCarregados = false;
  String? _erroCarregamento;
  String? _emailDosDados;

  @override
  void initState() {
    super.initState();
    carregarEntregas();
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: AppColors.error),
    );
  }

  Future<void> carregarEntregas() async {
    if (!mounted || _consultandoEntregas) return;
    _consultandoEntregas = true;

    if (!_dadosCarregados && !carregando) {
      setState(() => carregando = true);
    }

    try {
      final empresaEmail = await EmpresaService.empresaLogada();
      if (!mounted) return;
      if (empresaEmail == null || empresaEmail.trim().isEmpty) {
        throw const ApiException(
          'Sua sessão expirou. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }

      if (_emailDosDados != null && _emailDosDados != empresaEmail) {
        setState(() {
          entregas = [];
          _dadosCarregados = false;
          _emailDosDados = null;
          carregando = true;
        });
      }

      final entregadorEmail = widget.entregadorEmail;
      final resultado =
          await (entregadorEmail != null && entregadorEmail.isNotEmpty
                  ? EmpresaListaEntregasService.buscarEntregasDoEntregador(
                      entregadorEmail,
                    )
                  : EmpresaListaEntregasService.buscarEntregas())
              .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      final dados = <Map<String, dynamic>>[];
      for (final item in resultado) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Formato inválido de entrega');
        }
        final valor = item['valor'];
        final entregue = item['entregue'];
        if ((valor != null && (valor is! num || !valor.isFinite)) ||
            (entregue != null && entregue is! bool)) {
          throw const FormatException('Dados inválidos de entrega');
        }
        dados.add(item);
      }

      final sessaoAtual = await EmpresaService.empresaLogada();
      if (!mounted) return;
      if (sessaoAtual != empresaEmail) {
        throw const ApiException(
          'Sua sessão foi alterada. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }

      setState(() {
        entregas = dados;
        _dadosCarregados = true;
        _emailDosDados = empresaEmail;
        _erroCarregamento = null;
      });
    } catch (e) {
      if (!mounted) return;
      final mensagem = e is TimeoutException
          ? 'O servidor demorou para responder. Atualize as entregas e tente novamente.'
          : ApiService.mensagemErro(
              e,
              mensagemPadrao:
                  'Não foi possível carregar as entregas. Tente novamente.',
            );
      final acessoNegado =
          e is ApiException && (e.statusCode == 401 || e.statusCode == 403);
      setState(() {
        if (acessoNegado) {
          entregas = [];
          _dadosCarregados = false;
          _emailDosDados = null;
        }
        _erroCarregamento = mensagem;
      });
      _mostrarErro(
        _dadosCarregados
            ? '$mensagem Exibindo os últimos dados disponíveis.'
            : mensagem,
      );
    } finally {
      _consultandoEntregas = false;
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  Future<void> _abrirDetalhes(Map<String, dynamic> entrega) async {
    if (!mounted || _abrindoDetalhes) return;
    _abrindoDetalhes = true;
    try {
      final resultado = await context.push<bool>(
        '/empresa/entregas/detalhes',
        extra: entrega,
      );
      if (!mounted) return;
      if (resultado == true) {
        await carregarEntregas();
      }
    } catch (e) {
      _mostrarErro(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível abrir os detalhes da entrega. Tente novamente.',
        ),
      );
    } finally {
      _abrindoDetalhes = false;
    }
  }

  String statusEntrega(Map<String, dynamic> entrega) {
    final status = (entrega['status'] ?? '').toString();

    if (status.isNotEmpty) {
      return status;
    }

    final entregue = entrega['entregue'] ?? false;

    return entregue ? 'ENTREGUE' : 'PENDENTE';
  }

  Color corStatus(String status) {
    switch (status) {
      case 'ENTREGUE':
        return AppColors.success;
      case 'EM_ROTA':
        return Colors.blue;
      case 'NAO_ENTREGUE':
        return AppColors.error;
      case 'CANCELADA':
        return Colors.grey;
      case 'PENDENTE':
      default:
        return AppColors.warning;
    }
  }

  String textoStatus(String status) {
    switch (status) {
      case 'ENTREGUE':
        return 'Entregue';
      case 'EM_ROTA':
        return 'Em rota';
      case 'NAO_ENTREGUE':
        return 'Não entregue';
      case 'CANCELADA':
        return 'Cancelada';
      case 'PENDENTE':
      default:
        return 'Pendente';
    }
  }

  IconData iconeStatus(String status) {
    switch (status) {
      case 'ENTREGUE':
        return Icons.check_circle;
      case 'EM_ROTA':
        return Icons.local_shipping;
      case 'NAO_ENTREGUE':
        return Icons.report_problem;
      case 'CANCELADA':
        return Icons.cancel;
      case 'PENDENTE':
      default:
        return Icons.pending;
    }
  }

  List<dynamic> get entregasFiltradas {
    final pesquisa = pesquisaController.text.trim().toLowerCase();

    return entregas.where((entrega) {
      final mapa = Map<String, dynamic>.from(entrega);

      final cliente = (mapa['cliente'] ?? '').toString().toLowerCase();
      final endereco = (mapa['endereco'] ?? '').toString().toLowerCase();
      final id = (mapa['id'] ?? '').toString().toLowerCase();
      final status = statusEntrega(mapa);

      if (status == 'CANCELADA') {
        return false;
      }

      final batePesquisa =
          cliente.contains(pesquisa) ||
          endereco.contains(pesquisa) ||
          id.contains(pesquisa);

      final bateFiltro =
          filtro == 'todas' ||
          filtro == 'pendentes' && status == 'PENDENTE' ||
          filtro == 'em_rota' && status == 'EM_ROTA' ||
          filtro == 'entregues' && status == 'ENTREGUE' ||
          filtro == 'nao_entregues' && status == 'NAO_ENTREGUE';

      return batePesquisa && bateFiltro;
    }).toList();
  }

  Widget chipFiltro(String valor, String texto, IconData icon) {
    final selecionado = filtro == valor;
    final theme = Theme.of(context);

    return ChoiceChip(
      selected: selecionado,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: selecionado
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(texto),
        ],
      ),
      selectedColor: AppColors.primary,
      backgroundColor: theme.cardColor,
      labelStyle: TextStyle(
        color: selecionado ? Colors.white : theme.colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selecionado
              ? AppColors.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      onSelected: (_) {
        setState(() {
          filtro = valor;
        });
      },
    );
  }

  Widget badgeStatus(String status) {
    final cor = corStatus(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconeStatus(status), color: cor, size: 15),
          const SizedBox(width: 4),
          Text(
            textoStatus(status),
            style: TextStyle(
              color: cor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget cardEntrega(Map<String, dynamic> entrega) {
    final theme = Theme.of(context);
    final status = statusEntrega(entrega);

    final cliente = entrega['cliente'] ?? 'Cliente não informado';
    final endereco = entrega['endereco'] ?? 'Endereço não informado';
    final valorNum = (entrega['valor'] as num?)?.toDouble() ?? 0.0;
    final id = entrega['id'] ?? '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.18 : 0.05,
            ),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _abrirDetalhes(entrega),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                    child: const Icon(
                      Icons.inventory_2,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cliente.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  badgeStatus(status),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 19,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      endereco.toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.attach_money,
                    size: 19,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'R\$ ${valorNum.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'ID #$id',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    pesquisaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lista = entregasFiltradas;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: widget.entregadorEmail == null
              ? 'Voltar ao início'
              : 'Voltar ao perfil do entregador',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.entregadorEmail != null) {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/empresa/entregadores');
              }
            } else {
              context.go('/empresa/inicio');
            }
          },
        ),
        title: Text(
          widget.entregadorNome == null
              ? 'Minhas Entregas'
              : 'Entregas de ${widget.entregadorNome}',
        ),
        centerTitle: true,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: carregarEntregas,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  TextField(
                    controller: pesquisaController,
                    onChanged: (_) {
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar por cliente, endereço ou ID',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: pesquisaController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                pesquisaController.clear();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        chipFiltro('todas', 'Todas', Icons.list),
                        const SizedBox(width: 8),
                        chipFiltro('pendentes', 'Pendentes', Icons.pending),
                        const SizedBox(width: 8),
                        chipFiltro('em_rota', 'Em rota', Icons.local_shipping),
                        const SizedBox(width: 8),
                        chipFiltro(
                          'entregues',
                          'Entregues',
                          Icons.check_circle,
                        ),
                        const SizedBox(width: 8),
                        chipFiltro(
                          'nao_entregues',
                          'Não entregues',
                          Icons.report_problem,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (lista.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 58,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            !_dadosCarregados && _erroCarregamento != null
                                ? 'Não foi possível carregar as entregas. Puxe para atualizar.'
                                : 'Nenhuma entrega encontrada',
                            textAlign:
                                !_dadosCarregados && _erroCarregamento != null
                                ? TextAlign.center
                                : null,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...lista.map((entrega) {
                      return cardEntrega(Map<String, dynamic>.from(entrega));
                    }),
                ],
              ),
            ),
    );
  }
}
