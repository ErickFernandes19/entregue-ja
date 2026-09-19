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

      if (email == null) {
        carregando = false;
        notifyListeners();
        return;
      }

      final lista = await ApiService.buscarEntregasDoEntregador(email);

      _repository.entregas.clear();

      for (final item in lista) {
        _repository.adicionarEntrega(
          EntregaModel.fromJson(Map<String, dynamic>.from(item)),
        );
      }

      _repository.ordenarEntregas();
    } catch (e) {
      debugPrint('Erro ao carregar entregas no provider: $e');
    } finally {
      carregando = false;
      notifyListeners();
    }
  }

  Future<void> adicionarEntrega(EntregaModel entrega) async {
    _repository.adicionarEntrega(entrega);
    _repository.ordenarEntregas();

    notifyListeners();
  }

  Future<void> removerEntrega(int index) async {
    if (index < 0 || index >= entregas.length) {
      return;
    }

    _repository.removerEntrega(index);

    notifyListeners();
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

    entrega.entregue = true;
    entrega.status = 'ENTREGUE';

    _repository.ordenarEntregas();

    notifyListeners();
  }

  Future<void> atualizarLista() async {
    await carregarEntregasDoBackend();
  }
}
