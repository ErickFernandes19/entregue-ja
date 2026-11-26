import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/empresa_service.dart';
import '../theme/app_colors.dart';

class MeusEntregadoresPage extends StatefulWidget {
  const MeusEntregadoresPage({super.key});

  @override
  State<MeusEntregadoresPage> createState() => _MeusEntregadoresPageState();
}

class _MeusEntregadoresPageState extends State<MeusEntregadoresPage> {
  List<dynamic> entregadores = [];
  bool carregando = true;
  bool _consultando = false;
  bool _abrindoPerfil = false;
  String? _erroCarregamento;
  String? _empresaDosDados;

  @override
  void initState() {
    super.initState();
    carregarEntregadores();
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: AppColors.error),
    );
  }

  Future<void> carregarEntregadores() async {
    if (!mounted || _consultando) return;
    _consultando = true;

    try {
      final empresa = await EmpresaService.empresaLogada();
      if (!mounted) return;

      if (empresa == null || empresa.trim().isEmpty) {
        throw const ApiException(
          'Sua sessão expirou. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }

      if (_empresaDosDados != null && _empresaDosDados != empresa) {
        setState(() {
          entregadores = [];
          _empresaDosDados = null;
          _erroCarregamento = null;
          carregando = true;
        });
      }

      final resultado = await EmpresaService.buscarEntregadores(
        lancarErro: true,
      );
      if (!mounted) return;

      final empresaAtual = await EmpresaService.empresaLogada();
      if (!mounted) return;
      if (empresaAtual != empresa) {
        throw const ApiException(
          'Sua sessão mudou. Entre novamente ou atualize os dados.',
          statusCode: 401,
        );
      }

      final lista = <Map<String, dynamic>>[];
      for (final item in resultado) {
        if (item is! Map) {
          throw const FormatException('Registro de entregador inválido.');
        }
        final dados = Map<String, dynamic>.from(item);
        final email = dados['email']?.toString().trim() ?? '';
        if (email.isEmpty) {
          throw const FormatException('E-mail do entregador ausente.');
        }
        lista.add(dados);
      }

      setState(() {
        entregadores = lista;
        _empresaDosDados = empresa;
        _erroCarregamento = null;
      });
    } catch (e) {
      if (!mounted) return;
      final mensagem = ApiService.mensagemErro(
        e,
        mensagemPadrao:
            'Não foi possível carregar os entregadores. Tente novamente.',
      );
      final semAcesso =
          e is ApiException && (e.statusCode == 401 || e.statusCode == 403);

      setState(() {
        if (semAcesso) {
          entregadores = [];
          _empresaDosDados = null;
        }
        _erroCarregamento = mensagem;
      });
      _mostrarErro(
        entregadores.isNotEmpty
            ? '$mensagem Exibindo os últimos dados disponíveis.'
            : mensagem,
      );
    } finally {
      _consultando = false;
      if (mounted && carregando) {
        setState(() => carregando = false);
      }
    }
  }

  Future<void> _abrirPerfil(dynamic entregador) async {
    if (!mounted || _abrindoPerfil || _consultando) return;
    _abrindoPerfil = true;
    try {
      final empresa = await EmpresaService.empresaLogada();
      if (!mounted) return;
      if (empresa == null || empresa != _empresaDosDados) {
        setState(() {
          entregadores = [];
          _empresaDosDados = null;
          _erroCarregamento =
              'Sua sessão mudou ou expirou. Atualize os dados ou entre novamente.';
        });
        _mostrarErro(_erroCarregamento!);
        return;
      }

      final atualizado = await context.push<bool>(
        '/empresa/entregadores/perfil',
        extra: Map<String, dynamic>.from(entregador),
      );
      if (!mounted) return;
      if (atualizado == true) {
        await carregarEntregadores();
      }
    } catch (e) {
      _mostrarErro(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível abrir o perfil do entregador. Tente novamente.',
        ),
      );
    } finally {
      _abrindoPerfil = false;
    }
  }

  String formatarData(String? data) {
    if (data == null || data.isEmpty) {
      return 'Data não informada';
    }

    try {
      final date = DateTime.parse(data);

      final dia = date.day.toString().padLeft(2, '0');
      final mes = date.month.toString().padLeft(2, '0');
      final ano = date.year.toString();

      final hora = date.hour.toString().padLeft(2, '0');
      final minuto = date.minute.toString().padLeft(2, '0');

      return '$dia/$mes/$ano às $hora:$minuto';
    } catch (e) {
      return data;
    }
  }

  Widget cardEntregador(dynamic entregador) {
    final theme = Theme.of(context);

    final nome = entregador['nome'] ?? 'Entregador';
    final email = entregador['email'] ?? 'E-mail não informado';
    final dataVinculo = entregador['dataVinculo']?.toString();

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
              alpha: theme.brightness == Brightness.dark ? 0.16 : 0.04,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        onTap: () => _abrirPerfil(entregador),
        leading: CircleAvatar(
          radius: 23,
          backgroundColor: AppColors.primary.withValues(alpha: 0.14),
          child: const Icon(Icons.person, color: AppColors.primary),
        ),
        title: Text(
          nome.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '$email\n'
            'Vinculado em: ${formatarData(dataVinculo)}',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        isThreeLine: true,
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar ao início',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.go('/empresa/inicio');
          },
        ),
        title: const Text('Meus Entregadores'),
        centerTitle: true,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: carregarEntregadores,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.14,
                          ),
                          child: const Icon(
                            Icons.groups,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Total de entregadores',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          _empresaDosDados == null && _erroCarregamento != null
                              ? '—'
                              : '${entregadores.length}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (entregadores.isEmpty)
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
                            Icons.person_off,
                            size: 46,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _erroCarregamento == null
                                ? 'Nenhum entregador vinculado'
                                : 'Não foi possível carregar os entregadores',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _erroCarregamento == null
                                ? 'Quando um entregador aceitar o vínculo, ele aparecerá aqui.'
                                : '$_erroCarregamento Deslize para baixo para atualizar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...entregadores.map(cardEntregador),
                ],
              ),
            ),
    );
  }
}
