import 'package:flutter/material.dart';

import '../models/entrega_model.dart';
import '../repositories/entregas_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class EntregasProvider extends ChangeNotifier {
  final EntregasRepository _repository = EntregasRepository();

  bool carregando = false;
  Future<void>? _carregamentoAtual;
  String? _emailDasEntregas;
  bool _descartado = false;
  int _versao = 0;

  EntregasProvider() {
    carregarEntregasDoBackend();
  }

  List<EntregaModel> get entregas => _repository.entregas;

  void _notificar() {
    if (!_descartado) {
      notifyListeners();
    }
  }

  Future<void> carregarEntregasDoBackend() {
    if (_descartado) return Future<void>.value();
    if (_carregamentoAtual != null) return _carregamentoAtual!;

    final operacao = _carregarEntregas();
    _carregamentoAtual = operacao;
    return operacao.whenComplete(() {
      if (identical(_carregamentoAtual, operacao)) {
        _carregamentoAtual = null;
      }
    });
  }

  Future<void> _carregarEntregas() async {
    final versaoAtual = ++_versao;
    carregando = true;
    _notificar();

    try {
      final email = await AuthService.usuarioLogado();
      if (_descartado || versaoAtual != _versao) return;

      if (email == null || email.isEmpty) {
        _repository.entregas.clear();
        _emailDasEntregas = null;
        _notificar();
        debugPrint('Não foi possível carregar entregas: usuário não logado.');
        return;
      }

      if (_emailDasEntregas != null && _emailDasEntregas != email) {
        _repository.entregas.clear();
        _notificar();
      }
      _emailDasEntregas = email;

      final lista = await ApiService.buscarEntregasDoEntregador(email);
      if (_descartado || versaoAtual != _versao) return;

      final emailAtual = await AuthService.usuarioLogado();
      if (_descartado || versaoAtual != _versao) return;
      if (emailAtual != email) {
        _repository.entregas.clear();
        _emailDasEntregas = null;
        _notificar();
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
      _notificar();

      debugPrint('Entregas carregadas: ${_repository.entregas.length}');
    } catch (e) {
      debugPrint('Erro ao carregar entregas no provider: $e');
    } finally {
      if (!_descartado && versaoAtual == _versao) {
        carregando = false;
        _notificar();
      }
    }
  }

  Future<void> adicionarEntrega(EntregaModel entrega) async {
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
      debugPrint('Erro ao cadastrar entrega no backend: $e');
      rethrow;
    }
  }

  Future<bool> removerEntrega(int index) async {
    if (index < 0 || index >= entregas.length) return false;

    final entrega = entregas[index];
    if (entrega.id == null) {
      _repository.removerEntrega(index);
      _notificar();
      return true;
    }

    try {
      final sucesso = await ApiService.excluirEntrega(entrega.id!);
      if (!sucesso) return false;
      await _atualizarDepoisDeAlteracao();
      return true;
    } catch (e) {
      debugPrint('Erro ao remover entrega: $e');
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
    super.dispose();
  }
}
