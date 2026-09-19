import '../models/entrega_model.dart';

class EntregasRepository {
  final List<EntregaModel> _entregas = [];

  List<EntregaModel> get entregas => _entregas;

  void adicionarEntrega(EntregaModel entrega) {
    _entregas.add(entrega);
  }

  void removerEntrega(int index) {
    _entregas.removeAt(index);
  }

  void alternarStatusEntrega(int index) {
    _entregas[index].entregue = !_entregas[index].entregue;
  }

  void ordenarEntregas() {
    _entregas.sort((a, b) {
      if (a.entregue == b.entregue) {
        return 0;
      }

      return a.entregue ? 1 : -1;
    });
  }
}
