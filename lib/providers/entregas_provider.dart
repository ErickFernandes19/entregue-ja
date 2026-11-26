import 'package:flutter/material.dart';

import '../models/entrega_model.dart';
import '../repositories/entregas_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/localizacao_entregador_service.dart';

class EntregasProvider extends ChangeNotifier {
  final EntregasRepository _repository = EntregasRepository();
  final LocalizacaoEntregadorService _localizacao =
      LocalizacaoEntregadorService();

  bool carregando = false;
  String? _erroCarregamento;
  Future<void>? _carregamentoAtual;
  String? _emailDasEntregas;
  String? _tokenDasEntregas;
  bool _descartado = false;
  int _versao = 0;

  EntregasProvider() {
    AuthService.encerrandoSessao.addListener(_aoAlterarEncerramentoSessao);
    carregarEntregasDoBackend();
  }

  List<EntregaModel> get entregas => _repository.entregas;
  String? get erroCarregamento => _erroCarregamento;

  void _notificar() {
    if (!_descartado) {
      notifyListeners();
    }
  }

  void _limparSessaoDasEntregas() {
    _localizacao.parar();
    _repository.entregas.clear();
    _emailDasEntregas = null;
    _tokenDasEntregas = null;
    _erroCarregamento = null;
  }

  void _aoAlterarEncerramentoSessao() {
    if (_descartado || !AuthService.encerrandoSessao.value) return;

    _versao++;
    _carregamentoAtual = null;
    carregando = false;
    _limparSessaoDasEntregas();
    _notificar();
  }

  bool _carregamentoValido(int versao) =>
      !_descartado && !AuthService.encerrandoSessao.value && versao == _versao;

  Future<void> carregarEntregasDoBackend() {
    if (_descartado || AuthService.encerrandoSessao.value) {
      return Future<void>.value();
    }
    if (_carregamentoAtual != null) return _carregamentoAtual!;

    final versaoAtual = ++_versao;
    late final Future<void> operacao;
    operacao = Future<void>.microtask(() => _carregarEntregas(versaoAtual))
        .whenComplete(() {
          if (identical(_carregamentoAtual, operacao)) {
            _carregamentoAtual = null;
          }
        });
    _carregamentoAtual = operacao;
    return operacao;
  }

  Future<void> _carregarEntregas(int versaoAtual) async {
    if (!_carregamentoValido(versaoAtual)) return;

    carregando = true;
    _erroCarregamento = null;
    _notificar();

    try {
      if (!_carregamentoValido(versaoAtual)) return;
      final email = await AuthService.usuarioLogado();
      final token = await AuthService.obterToken();
      if (!_carregamentoValido(versaoAtual)) return;

      if (email == null || email.isEmpty || token == null || token.isEmpty) {
        _limparSessaoDasEntregas();
        debugPrint('Não foi possível carregar entregas: usuário não logado.');
        return;
      }

      if (_emailDasEntregas != email || _tokenDasEntregas != token) {
        _limparSessaoDasEntregas();
      }
      _emailDasEntregas = email;
      _tokenDasEntregas = token;

      final lista = await ApiService.buscarEntregasDoEntregador(email);
      if (!_carregamentoValido(versaoAtual)) return;

      final emailAtual = await AuthService.usuarioLogado();
      final tokenAtual = await AuthService.obterToken();
      if (!_carregamentoValido(versaoAtual)) return;
      if (emailAtual != email || tokenAtual != token) {
        _limparSessaoDasEntregas();
        return;
      }

      final novasEntregas = <EntregaModel>[];
      for (final item in lista) {
        novasEntregas.add(
          EntregaModel.fromJson(Map<String, dynamic>.from(item)),
        );
      }

      _repository.entregas
        ..clear()
        ..addAll(novasEntregas);
      _repository.ordenarEntregas();

      final possuiEntregasEmRota = novasEntregas.any(
        (entrega) =>
            entrega.id != null &&
            entrega.status.toString().trim().toUpperCase() == 'EM_ROTA',
      );

      if (possuiEntregasEmRota) {
        _localizacao.iniciar(email: email, token: token);
      } else {
        _localizacao.parar();
      }

      debugPrint('Entregas carregadas: ${_repository.entregas.length}');
    } catch (e) {
      if (_carregamentoValido(versaoAtual)) {
        _erroCarregamento = ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível carregar suas entregas. Tente novamente.',
        );
        debugPrint('Erro ao carregar entregas no provider: ${e.runtimeType}');
      }
    } finally {
      if (_carregamentoValido(versaoAtual)) {
        carregando = false;
        _notificar();
      }
    }
  }

  Future<void> adicionarEntrega(EntregaModel entrega) async {
    if (_descartado) return;
    if (AuthService.encerrandoSessao.value) {
      throw const ApiException(
        'Sua sessão foi encerrada. Entre novamente na sua conta.',
        statusCode: 401,
      );
    }

    try {
      if (entrega.id != null) {
        final jaExiste = _repository.entregas.any(
          (item) => item.id == entrega.id,
        );

        if (!jaExiste) {
          _repository.adicionarEntrega(entrega);
          _repository.ordenarEntregas();
          _notificar();
        }
        return;
      }

      await ApiService.cadastrarEntregaEntregador(
        cliente: entrega.cliente,
        endereco: entrega.endereco,
        valor: entrega.valor,
        complemento: entrega.complemento,
        observacao: entrega.observacao,
        latitude: entrega.latitude,
        longitude: entrega.longitude,
      );

      await _atualizarDepoisDeAlteracao();
    } catch (e) {
      debugPrint('Erro ao cadastrar entrega no backend: ${e.runtimeType}');
      if (e is ApiException) rethrow;
      throw ApiException(
        ApiService.mensagemErro(
          e,
          mensagemPadrao:
              'Não foi possível cadastrar a entrega. Tente novamente.',
        ),
      );
    }
  }

  Future<bool> removerEntrega(int index, {bool lancarErro = false}) async {
    if (_descartado) return false;
    if (AuthService.encerrandoSessao.value) {
      if (lancarErro) {
        throw const ApiException(
          'Sua sessão foi encerrada. Entre novamente na sua conta.',
          statusCode: 401,
        );
      }
      return false;
    }
    if (index < 0 || index >= entregas.length) {
      if (lancarErro) {
        throw const ApiException(
          'A lista de entregas mudou. Atualize e tente novamente.',
        );
      }
      return false;
    }

    final entrega = entregas[index];
    if (entrega.id == null) {
      _repository.removerEntrega(index);
      _notificar();
      return true;
    }

    try {
      final sucesso = await ApiService.excluirEntrega(
        entrega.id!,
        lancarErro: lancarErro,
      );
      if (!sucesso) return false;
      await _atualizarDepoisDeAlteracao();
      return true;
    } catch (e) {
      debugPrint('Erro ao remover entrega: ${e.runtimeType}');
      if (lancarErro) {
        if (e is ApiException) rethrow;
        throw ApiException(
          ApiService.mensagemErro(
            e,
            mensagemPadrao:
                'Não foi possível remover a entrega. Tente novamente.',
          ),
        );
      }
      return false;
    }
  }

  Future<void> alternarStatusEntrega(int index) async {
    if (index < 0 || index >= entregas.length) return;

    throw StateError(
      'A finalização da entrega deve ser realizada pela tela '
      'de finalização, com fotografia e localização GPS.',
    );
  }

  Future<void> _atualizarDepoisDeAlteracao() async {
    final carregamento = _carregamentoAtual;
    if (carregamento != null) {
      await carregamento;
    }
    await carregarEntregasDoBackend();
  }

  Future<void> atualizarLista() async {
    await carregarEntregasDoBackend();
  }

  @override
  void dispose() {
    _descartado = true;
    _versao++;
    AuthService.encerrandoSessao.removeListener(_aoAlterarEncerramentoSessao);
    _localizacao.dispose();
    super.dispose();
  }
}
