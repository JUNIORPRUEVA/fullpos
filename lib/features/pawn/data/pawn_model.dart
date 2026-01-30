/// Modelo de empeño
/// TODO: Implementar modelo completo
class PawnModel {
  final int? id;
  final int clientId;
  final String descripcion;
  final double monto;
  final String status;
  final int createdAtMs;

  PawnModel({
    this.id,
    required this.clientId,
    required this.descripcion,
    required this.monto,
    required this.status,
    required this.createdAtMs,
  });

  factory PawnModel.fromMap(Map<String, dynamic> map) {
    return PawnModel(
      id: map['id'] as int?,
      clientId: map['client_id'] as int,
      descripcion: map['descripcion'] as String,
      monto: map['monto'] as double,
      status: map['status'] as String,
      createdAtMs: map['created_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'client_id': clientId,
      'descripcion': descripcion,
      'monto': monto,
      'status': status,
      'created_at_ms': createdAtMs,
    };
  }
}
