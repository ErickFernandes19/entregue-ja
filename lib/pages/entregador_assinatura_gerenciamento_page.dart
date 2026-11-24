import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/assinatura_service.dart';
import '../services/pagamento_assinatura_service.dart';

class EntregadorAssinaturaGerenciamentoPage extends StatefulWidget {
  const EntregadorAssinaturaGerenciamentoPage({super.key});

  @override
  State<EntregadorAssinaturaGerenciamentoPage> createState() =>
      _EntregadorAssinaturaGerenciamentoPageState();
}

class _EntregadorAssinaturaGerenciamentoPageState
    extends State<EntregadorAssinaturaGerenciamentoPage> {
  static const _tipoAssinatura = TipoContaAssinatura.entregador;
  static const _tipoPagamento = TipoContaPagamento.entregador;

  bool _carregando = true;
  bool _operando = false;
  bool _confirmando = false;
  bool _carregamentoEmCurso = false;
  String? _erroRecorrentes;
  List<Map<String, dynamic>> _recorrentes = [];

  bool get _ocupado => _carregando || _operando || _confirmando;
  String? _erro;
  Map<String, dynamic>? _assinatura;
  Map<String, dynamic>? _consumo;
  List<Map<String, dynamic>> _historico = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (!mounted || _operando || _confirmando || _carregamentoEmCurso) {
      return;
    }
    _carregamentoEmCurso = true;
    setState(() {
      _carregando = true;
      _erro = null;
      _erroRecorrentes = null;
      _assinatura = null;
      _consumo = null;
      _historico = [];
      _recorrentes = [];
    });

    try {
      await _carregarPlano();
      await _carregarRecorrentes();
    } finally {
      _carregamentoEmCurso = false;
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  Future<void> _carregarPlano() async {
    if (!mounted) {
      return;
    }
    try {
      final resultados = await Future.wait<dynamic>([
        AssinaturaService.buscarAtual(tipoConta: _tipoAssinatura),
        AssinaturaService.buscarHistorico(tipoConta: _tipoAssinatura),
        AssinaturaService.buscarConsumo(tipoConta: _tipoAssinatura),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _assinatura = resultados[0] as Map<String, dynamic>?;
        _historico = resultados[1] as List<Map<String, dynamic>>;
        _consumo = resultados[2] as Map<String, dynamic>;
        _erro = null;
      });
    } on AssinaturaException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _erro = e.mensagem);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(
        () => _erro = 'Não foi possível carregar os dados da assinatura.',
      );
    }
  }

  Future<void> _carregarRecorrentes() async {
    if (!mounted) {
      return;
    }
    try {
      final dados =
          await PagamentoAssinaturaService.listarAssinaturasRecorrentes(
            tipoConta: _tipoPagamento,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _recorrentes = dados;
        _erroRecorrentes = null;
      });
    } on PagamentoAssinaturaException catch (e) {
      if (mounted) {
        setState(() => _erroRecorrentes = e.mensagem);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _erroRecorrentes =
              'Não foi possível consultar as cobranças recorrentes.',
        );
      }
    }
  }

  String _rotulo(String? valor) {
    switch (valor) {
      case 'GRATUITO':
        return 'Gratuito';
      case 'ESSENCIAL':
        return 'Essencial';
      case 'PROFISSIONAL':
        return 'Profissional';
      case 'ATIVA':
        return 'Ativa';
      case 'PENDENTE':
        return 'Pendente';
      case 'CANCELADA':
        return 'Cancelada';
      case 'EXPIRADA':
        return 'Expirada';
      case 'AUTORIZADA':
        return 'Autorizada';
      case 'PAUSADA':
        return 'Pausada';
      case 'ENCERRADA':
        return 'Encerrada';
      case 'PREPARADA':
        return 'Preparada';
      case 'ENVIANDO':
        return 'Em processamento';
      case 'INCERTA':
        return 'Aguardando confirmação';
      case 'CONFIRMADA':
        return 'Confirmada';
      default:
        return valor?.isNotEmpty == true ? valor! : 'Não informado';
    }
  }

  String _data(dynamic valor) {
    if (valor == null) {
      return 'Não informada';
    }
    final data = DateTime.tryParse(valor.toString());
    if (data == null) {
      return 'Não informada';
    }
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  int? _inteiro(dynamic valor) {
    if (valor is int) {
      return valor;
    }
    if (valor is num && valor.isFinite && valor == valor.roundToDouble()) {
      return valor.toInt();
    }
    if (valor is String) {
      return int.tryParse(valor);
    }
    return null;
  }

  Future<void> _mostrarDetalhes({
    required String titulo,
    required String descricao,
    required IconData icone,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(icone),
            const SizedBox(width: 10),
            Expanded(child: Text(titulo)),
          ],
        ),
        content: Text(descricao),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _voltarAosPlanos() {
    Navigator.of(context).pop();
  }

  bool _temIdentificadorExterno(Map<String, dynamic> item) {
    final id = item['mercadoPagoAssinaturaId'];
    return id is String && id.trim().isNotEmpty;
  }

  bool _recorrenteAberta(Map<String, dynamic> item) {
    return const {'PENDENTE', 'AUTORIZADA', 'PAUSADA'}.contains(item['status']);
  }

  bool _podeCancelar(Map<String, dynamic> item) {
    final id = _inteiro(item['assinaturaId']);
    return id != null &&
        id > 0 &&
        _temIdentificadorExterno(item) &&
        _recorrenteAberta(item);
  }

  void _mensagem(String mensagem) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _consultarRecorrente(int id) async {
    if (_ocupado || !mounted) {
      return;
    }
    setState(() => _operando = true);
    try {
      final dados =
          await PagamentoAssinaturaService.consultarAssinaturaRecorrente(
            assinaturaId: id,
            tipoConta: _tipoPagamento,
          );
      if (!mounted) {
        return;
      }
      _mensagem(
        'Situação da cobrança: ${_rotulo(dados['status']?.toString())}.',
      );
    } on PagamentoAssinaturaException catch (e) {
      _mensagem(e.mensagem);
    } catch (_) {
      _mensagem('Não foi possível consultar a cobrança.');
    } finally {
      await _carregarPlano();
      await _carregarRecorrentes();
      if (mounted) {
        setState(() => _operando = false);
      }
    }
  }

  Future<void> _cancelarRecorrente(Map<String, dynamic> item) async {
    if (_ocupado || !mounted || !_podeCancelar(item)) {
      return;
    }
    final id = _inteiro(item['assinaturaId']);
    if (id == null || id <= 0) {
      return;
    }
    setState(() => _confirmando = true);
    bool? confirmou;
    try {
      confirmou = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancelar renovação automática?'),
          content: Text(
            'Deseja cancelar as próximas cobranças do plano ${_rotulo(item['plano']?.toString())}? '
            'Isso não solicita reembolso nem encerra imediatamente o período já pago. '
            'O cancelamento depende da confirmação do Mercado Pago.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Manter assinatura'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancelar renovação'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _confirmando = false);
      }
    }
    if (!mounted || confirmou != true || _ocupado) {
      return;
    }
    setState(() => _operando = true);
    try {
      final dados =
          await PagamentoAssinaturaService.cancelarAssinaturaRecorrente(
            assinaturaId: id,
            tipoConta: _tipoPagamento,
          );
      if (!mounted) {
        return;
      }
      if (_inteiro(dados['assinaturaId']) == id &&
          const {'CANCELADA', 'ENCERRADA'}.contains(dados['status'])) {
        _mensagem(
          'Cobrança recorrente encerrada. Consulte a validade do plano atual.',
        );
      } else {
        _mensagem(
          'Cancelamento ainda não confirmado. Consulte a situação da cobrança.',
        );
      }
    } on PagamentoAssinaturaException catch (e) {
      _mensagem('${e.mensagem} Consulte a situação antes de tentar novamente.');
    } catch (_) {
      _mensagem(
        'Não foi possível confirmar o cancelamento. Consulte a cobrança.',
      );
    } finally {
      await _carregarPlano();
      await _carregarRecorrentes();
      if (mounted) {
        setState(() => _operando = false);
      }
    }
  }

  Future<void> _abrirAutorizacao(Map<String, dynamic> item) async {
    if (_ocupado ||
        !mounted ||
        item['status'] != 'PENDENTE' ||
        item['estadoCriacao'] != 'CONFIRMADA' ||
        !_temIdentificadorExterno(item)) {
      return;
    }
    final uri = Uri.tryParse(item['urlAutorizacao']?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !const [
          'mercadopago.com',
          'mercadopago.com.br',
        ].any((host) => uri.host == host || uri.host.endsWith('.$host'))) {
      _mensagem('O endereço de autorização do Mercado Pago é inválido.');
      return;
    }
    setState(() => _operando = true);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _mensagem('Não foi possível abrir o Mercado Pago.');
      }
    } catch (_) {
      _mensagem('Não foi possível abrir o Mercado Pago.');
    } finally {
      if (mounted) {
        setState(() => _operando = false);
      }
    }
  }

  Widget _cardRecorrentes() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cobranças recorrentes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_carregando)
              const Center(child: CircularProgressIndicator())
            else if (_erroRecorrentes != null) ...[
              Text(_erroRecorrentes!),
              TextButton.icon(
                onPressed: _ocupado ? null : _carregar,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ] else if (_recorrentes.isEmpty)
              const Text('Nenhuma cobrança recorrente registrada.')
            else
              ..._recorrentes.map(_itemRecorrente),
            const SizedBox(height: 12),
            Text(
              'A autorização de uma cobrança recorrente não confirma o pagamento. O plano ativo e sua validade são informados separadamente pelo servidor.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemRecorrente(Map<String, dynamic> item) {
    final id = _inteiro(item['assinaturaId']);
    final status = item['status']?.toString();
    final criacao = item['estadoCriacao']?.toString();
    final valor = num.tryParse(item['valorMensal']?.toString() ?? '');
    final podeAutorizar =
        status == 'PENDENTE' &&
        criacao == 'CONFIRMADA' &&
        _temIdentificadorExterno(item) &&
        (item['urlAutorizacao']?.toString().isNotEmpty ?? false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            'Plano ${_rotulo(item['plano']?.toString())}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (valor != null && valor.isFinite && valor > 0)
            Text('R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}/mês'),
          Text('Situação: ${_rotulo(status)}'),
          Text('Registro: ${_data(item['dataCriacao'])}'),
          if (item['dataCancelamento'] != null)
            Text('Cancelamento: ${_data(item['dataCancelamento'])}'),
          if (criacao != 'CONFIRMADA')
            Text('Confirmação da contratação: ${_rotulo(criacao)}'),
          if (_recorrenteAberta(item) && !_temIdentificadorExterno(item))
            const Text(
              'Contratação ainda sem identificador externo. Aguarde a confirmação antes de contratar novamente.',
            ),
          if (status == 'CANCELADA' || status == 'ENCERRADA')
            const Text(
              'Renovação recorrente encerrada. A validade do plano atual é exibida acima.',
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (id != null && id > 0)
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => _consultarRecorrente(id),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Consultar situação'),
                ),
              if (podeAutorizar)
                FilledButton.icon(
                  onPressed: _ocupado ? null : () => _abrirAutorizacao(item),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Autorizar pagamento'),
                ),
              if (_podeCancelar(item))
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : () => _cancelarRecorrente(item),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar renovação'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _opcoesGerenciamento() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Alterar plano'),
            subtitle: const Text('Comparar os planos disponíveis'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _ocupado ? null : _voltarAosPlanos,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.autorenew),
            title: const Text('Renovação automática'),
            subtitle: const Text(
              'Consulte a situação das cobranças recorrentes',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _ocupado
                ? null
                : () => _mostrarDetalhes(
                    titulo: 'Renovação automática',
                    icone: Icons.autorenew,
                    descricao:
                        'O Pix não gera renovação automática. Para acompanhar ou cancelar cobranças recorrentes, utilize os controles da seção Cobranças recorrentes. A validade do plano atual é informada separadamente.',
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.credit_card_outlined),
            title: const Text('Forma de pagamento'),
            subtitle: const Text('Informações de cobrança e segurança'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _ocupado
                ? null
                : () => _mostrarDetalhes(
                    titulo: 'Forma de pagamento',
                    icone: Icons.credit_card_outlined,
                    descricao:
                        'Os dados de cartão são tratados pelo Mercado Pago. A alteração do cartão não está disponível nesta tela. Nenhuma cobrança é realizada nesta consulta.',
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final consumo = _consumo;
    final plano = _assinatura?['plano']?.toString();
    final consumoValido =
        consumo != null &&
        consumo['tipoConta'] == 'ENTREGADOR' &&
        consumo['periodo'] == 'DIARIO' &&
        consumo['plano'] == plano;
    final ilimitado = consumoValido && consumo['entregasIlimitadas'] == true;
    final usadas = consumoValido
        ? _inteiro(consumo['entregasUtilizadasHoje'])
        : null;
    final limite = consumoValido
        ? _inteiro(consumo['limiteEntregasDia'])
        : null;
    final restantes = consumoValido
        ? _inteiro(consumo['entregasDisponiveisHoje'])
        : null;
    const periodoTexto = 'hoje';
    const periodoTitulo = 'Período diário';
    final consumoCompleto =
        consumoValido &&
        usadas != null &&
        usadas >= 0 &&
        consumo['entregasIlimitadas'] is bool &&
        (ilimitado ||
            (limite != null &&
                limite > 0 &&
                restantes != null &&
                restantes >= 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha assinatura'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _ocupado ? null : _carregar,
            tooltip: 'Atualizar assinatura',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Gerencie seu plano',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Consulte as opções disponíveis para suas entregas independentes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assinatura atual',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_carregando)
                      const Center(child: CircularProgressIndicator())
                    else if (_erro != null) ...[
                      Text(_erro!),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _ocupado ? null : _carregar,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ] else if (_assinatura == null)
                      const Text(
                        'Ainda não há uma assinatura ativa registrada para esta conta.',
                      )
                    else ...[
                      Text('Plano: ${_rotulo(plano)}'),
                      const SizedBox(height: 6),
                      Text(
                        'Status: ${_rotulo(_assinatura!['status']?.toString())}',
                      ),
                      const SizedBox(height: 6),
                      Text('Início: ${_data(_assinatura!['dataInicio'])}'),
                      const SizedBox(height: 6),
                      Text(
                        'Vencimento: ${_data(_assinatura!['dataVencimento'])}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consumo de entregas independentes',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_carregando && _erro == null && consumoValido) ...[
                      Text(periodoTitulo, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                    ],
                    if (_carregando)
                      const Center(child: CircularProgressIndicator())
                    else if (_erro != null)
                      const Text('Consumo indisponível no momento.')
                    else if (!consumoCompleto)
                      const Text(
                        'Os dados de consumo estão indisponíveis ou incompletos.',
                      )
                    else ...[
                      Text('Utilizadas $periodoTexto: $usadas'),
                      const SizedBox(height: 8),
                      Text(
                        'Limite $periodoTexto: ${ilimitado ? 'Ilimitado' : limite.toString()}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Restantes $periodoTexto: ${ilimitado ? 'Ilimitadas' : restantes.toString()}',
                      ),
                      if (!ilimitado && limite != null && limite > 0) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: (usadas / limite).clamp(0.0, 1.0),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${((usadas / limite) * 100).clamp(0.0, 100.0).toStringAsFixed(0)}% do limite diário utilizado',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'As entregas atribuídas por empresas vinculadas não utilizam sua franquia pessoal.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Histórico de assinaturas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_carregando)
                      const Center(child: CircularProgressIndicator())
                    else if (_erro != null)
                      const Text('Histórico indisponível no momento.')
                    else if (_historico.isEmpty)
                      const Text('Nenhuma assinatura disponível para consulta.')
                    else
                      ..._historico.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_rotulo(item['plano']?.toString())),
                          subtitle: Text(
                            'Status: ${_rotulo(item['status']?.toString())}\n'
                            'Início: ${_data(item['dataInicio'])}',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _cardRecorrentes(),
            if (_operando) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 20),
            Text(
              'Gerenciar assinatura',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _opcoesGerenciamento(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _ocupado ? null : _voltarAosPlanos,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar aos planos'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'As informações de assinatura, histórico e consumo são atualizadas pelo servidor.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
