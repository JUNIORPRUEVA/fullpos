/// Modelo de Caja
class CashBoxModel {
  final int id;
  final int? sessionId; // ID de sesión de usuario
  final double openingBalance; // Saldo inicial
  final double closingBalance; // Saldo final
  final double expectedBalance; // Saldo esperado (suma de ventas)
  final double difference; // Diferencia: expected - closing
  final String status; // 'OPEN' o 'CLOSED'
  final int openedAtMs;
  final int? closedAtMs;
  final String? notes; // Notas del cierre
  final int createdAtMs;
  final int updatedAtMs;

  CashBoxModel({
    required this.id,
    this.sessionId,
    required this.openingBalance,
    required this.closingBalance,
    required this.expectedBalance,
    required this.difference,
    required this.status,
    required this.openedAtMs,
    this.closedAtMs,
    this.notes,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Convertir modelo a Map (para base de datos)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'opening_balance': openingBalance,
      'closing_balance': closingBalance,
      'expected_balance': expectedBalance,
      'difference': difference,
      'status': status,
      'opened_at_ms': openedAtMs,
      'closed_at_ms': closedAtMs,
      'notes': notes,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
    };
  }

  /// Crear modelo desde Map (desde base de datos)
  factory CashBoxModel.fromMap(Map<String, dynamic> map) {
    return CashBoxModel(
      id: map['id'] as int,
      sessionId: map['session_id'] as int?,
      openingBalance: (map['opening_balance'] as num).toDouble(),
      closingBalance: (map['closing_balance'] as num).toDouble(),
      expectedBalance: (map['expected_balance'] as num).toDouble(),
      difference: (map['difference'] as num).toDouble(),
      status: map['status'] as String,
      openedAtMs: map['opened_at_ms'] as int,
      closedAtMs: map['closed_at_ms'] as int?,
      notes: map['notes'] as String?,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
    );
  }

  /// copyWith para crear copias modificadas
  CashBoxModel copyWith({
    int? id,
    int? sessionId,
    double? openingBalance,
    double? closingBalance,
    double? expectedBalance,
    double? difference,
    String? status,
    int? openedAtMs,
    int? closedAtMs,
    String? notes,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return CashBoxModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      openingBalance: openingBalance ?? this.openingBalance,
      closingBalance: closingBalance ?? this.closingBalance,
      expectedBalance: expectedBalance ?? this.expectedBalance,
      difference: difference ?? this.difference,
      status: status ?? this.status,
      openedAtMs: openedAtMs ?? this.openedAtMs,
      closedAtMs: closedAtMs ?? this.closedAtMs,
      notes: notes ?? this.notes,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
