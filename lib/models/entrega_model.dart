class EntregaModel {
  final int? id;

  final String endereco;
  final String cliente;
  final double valor;
  final String observacao;

  bool entregue;
  String status;

  EntregaModel({
    this.id,
    required this.endereco,
    required this.cliente,
    required this.valor,
    required this.observacao,
    this.entregue = false,
    this.status = 'PENDENTE',
  });

  bool get estaPendente => status == 'PENDENTE';

  bool get estaEmRota => status == 'EM_ROTA';

  bool get estaEntregue => status == 'ENTREGUE';

  bool get naoFoiEntregue => status == 'NAO_ENTREGUE';

  bool get estaFinalizada => status == 'ENTREGUE' || status == 'NAO_ENTREGUE';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'endereco': endereco,
      'cliente': cliente,
      'valor': valor,
      'observacao': observacao,
      'entregue': entregue,
      'status': status,
    };
  }

  factory EntregaModel.fromJson(Map<String, dynamic> json) {
    final entregue = json['entregue'] == true;

    String status = json['status']?.toString() ?? '';

    if (status.isEmpty) {
      status = entregue ? 'ENTREGUE' : 'PENDENTE';
    }

    return EntregaModel(
      id: json['id'],
      endereco: json['endereco']?.toString() ?? '',
      cliente: json['cliente']?.toString() ?? '',
      valor: (json['valor'] as num?)?.toDouble() ?? 0.0,
      observacao: json['observacao']?.toString() ?? '',
      entregue: entregue,
      status: status,
    );
  }
}
