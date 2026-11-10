import 'package:flutter/material.dart';

import '../models/entrega_model.dart';
import '../repositories/entregas_repository.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class EntregasProvider extends ChangeNotifier {
  final EntregasRepository _repository = EntregasRepository();

  bool carregando = false;

  EntregasProvider() {
    carregarEntregasDoBackend();
  }

  List<EntregaModel> get entregas => _repository.entregas;

  Future<void> carregarEntregasDoBackend() async {
    carregando = true;
    notifyListeners();

    try {
      final email = await AuthService.usuarioLogado();

      if (email == null || email.isEmpty) {
        debugPrint('Não foi possível carregar entregas: usuário não logado.');
        return;
      }

      final lista = await ApiService.buscarEntregasDoEntregador(email);

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

      debugPrint('Entregas carregadas: ${_repository.entregas.length}');
    } catch (e) {
      debugPrint('Erro ao carregar entregas no provider: $e');
    } finally {
      carregando = false;
      notifyListeners();
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
          notifyListeners();
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

      await carregarEntregasDoBackend();
    } catch (e) {
      debugPrint('Erro ao cadastrar entrega no backend: $e');
      rethrow;
    }
  }

  Future<bool> removerEntrega(int index) async {
    if (index < 0 || index >= entregas.length) {
      return false;
    }

    final entrega = entregas[index];

    if (entrega.id == null) {
      _repository.removerEntrega(index);
      notifyListeners();
      return true;
    }

    try {
      final sucesso = await ApiService.excluirEntrega(entrega.id!);

      if (!sucesso) {
        return false;
      }

      await carregarEntregasDoBackend();

      return true;
    } catch (e) {
      debugPrint('Erro ao remover entrega: $e');
      return false;
    }
  }

  Future<void> alternarStatusEntrega(int index) async {
    if (index < 0 || index >= entregas.length) {
      return;
    }

    final entrega = entregas[index];

    if (entrega.id == null) {
      return;
    }

    final sucesso = await ApiService.atualizarStatusEntrega(entrega.id!);

    if (!sucesso) {
      return;
    }

    await carregarEntregasDoBackend();
  }

  Future<void> atualizarLista() async {
    await carregarEntregasDoBackend();
  }
}
