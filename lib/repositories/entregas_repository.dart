import '../models/entrega_model.dart';

class EntregasRepository {
  final List<EntregaModel> _entregas = [];

  List<EntregaModel> get entregas => _entregas;

  void adicionarEntrega(EntregaModel entrega) {
    final id = entrega.id;

    if (id != null) {
      final index = _entregas.indexWhere((item) => item.id == id);
      if (index != -1) {
        _entregas[index] = entrega;
        return;
      }
    }

    _entregas.add(entrega);
  }

  void removerEntrega(int index) {
    if (index < 0 || index >= _entregas.length) {
      return;
    }

    _entregas.removeAt(index);
  }

  void alternarStatusEntrega(int index) {
    if (index < 0 || index >= _entregas.length) {
      return;
    }

    _entregas[index].entregue = !_entregas[index].entregue;
  }

  void ordenarEntregas() {
    final posicoes = <EntregaModel, int>{};
    for (var i = 0; i < _entregas.length; i++) {
      posicoes[_entregas[i]] = i;
    }

    _entregas.sort((a, b) {
      final comparacao = _prioridadeStatus(
        a.status,
      ).compareTo(_prioridadeStatus(b.status));
      if (comparacao != 0) {
        return comparacao;
      }

      return (posicoes[a] ?? 0).compareTo(posicoes[b] ?? 0);
    });
  }

  int _prioridadeStatus(String status) {
    switch (status.trim().toUpperCase()) {
      case 'EM_ROTA':
        return 0;
      case 'PENDENTE':
        return 1;
      case 'NAO_ENTREGUE':
        return 2;
      case 'ENTREGUE':
        return 3;
      case 'CANCELADA':
        return 4;
      default:
        return 5;
    }
  }
}
