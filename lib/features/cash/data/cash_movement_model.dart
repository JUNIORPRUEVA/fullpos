/// Modelo de Movimiento de Caja
class CashMovementModel {
  final int? id;
  final int sessionId;
  final String type; // IN / OUT
  final double amount;
  final String reason;
  final int createdAtMs;
  final int userId;

  CashMovementModel({
    this.id,
    required this.sessionId,
    required this.type,
    required this.amount,
    required this.reason,
    required this.createdAtMs,
    required this.userId,
  });

  bool get isIn => type == CashMovementType.income;
  bool get isOut => type == CashMovementType.outcome;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'type': type,
      'amount': amount,
      'reason': reason,
      'created_at_ms': createdAtMs,
      'user_id': userId,
    };
  }

  factory CashMovementModel.fromMap(Map<String, dynamic> map) {
    return CashMovementModel(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      reason: map['reason'] as String? ?? map['note'] as String? ?? '',
      createdAtMs: map['created_at_ms'] as int,
      userId: map['user_id'] as int? ?? 1,
    );
  }

  CashMovementModel copyWith({
    int? id,
    int? sessionId,
    String? type,
    double? amount,
    String? reason,
    int? createdAtMs,
    int? userId,
  }) {
    return CashMovementModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      reason: reason ?? this.reason,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      userId: userId ?? this.userId,
    );
  }
}

/// Constantes para tipos de movimiento
class CashMovementType {
  CashMovementType._();
  static const String income = 'IN';
  static const String outcome = 'OUT';
}
