class EntregaModel {
  final int? id;

  final String endereco;
  final String complemento;
  final String cliente;
  final double valor;
  final String observacao;
  final double? latitude;
  final double? longitude;

  bool entregue;
  String status;

  EntregaModel({
    this.id,
    required this.endereco,
    this.complemento = '',
    required this.cliente,
    required this.valor,
    required this.observacao,
    this.entregue = false,
    this.status = 'PENDENTE',
    this.latitude,
    this.longitude,
  });

  bool get estaPendente => status == 'PENDENTE';

  bool get estaEmRota => status == 'EM_ROTA';

  bool get estaEntregue => status == 'ENTREGUE';

  bool get naoFoiEntregue => status == 'NAO_ENTREGUE';

  bool get estaCancelada => status == 'CANCELADA';

  bool get estaFinalizada =>
      status == 'ENTREGUE' || status == 'NAO_ENTREGUE' || status == 'CANCELADA';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'endereco': endereco,
      'complemento': complemento,
      'cliente': cliente,
      'valor': valor,
      'observacao': observacao,
      'entregue': entregue,
      'status': status,
      'latitude': latitude,
      'longitude': longitude,
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
      complemento: json['complemento']?.toString() ?? '',
      cliente: json['cliente']?.toString() ?? '',
      valor: (json['valor'] as num?)?.toDouble() ?? 0.0,
      observacao: json['observacao']?.toString() ?? '',
      entregue: entregue,
      status: status,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}
