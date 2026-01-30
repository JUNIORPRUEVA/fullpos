/// Modelo para movimientos de caja (ingresos/egresos)
class CashMovementModel {
  final int? id;
  final int sessionId;
  final String type; // 'in' | 'out'
  final double amount;
  final String? note;
  final int createdAtMs;

  CashMovementModel({
    this.id,
    required this.sessionId,
    required this.type,
    required this.amount,
    this.note,
    required this.createdAtMs,
  });

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  bool get isIncome => type == CashMovementType.income;
  bool get isExpense => type == CashMovementType.expense;

  factory CashMovementModel.fromMap(Map<String, dynamic> map) {
    return CashMovementModel(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      note: map['note'] as String?,
      createdAtMs: map['created_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'type': type,
      'amount': amount,
      'note': note,
      'created_at_ms': createdAtMs,
    };
  }

  CashMovementModel copyWith({
    int? id,
    int? sessionId,
    String? type,
    double? amount,
    String? note,
    int? createdAtMs,
  }) {
    return CashMovementModel(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }
}

/// Tipos de movimiento de caja
class CashMovementType {
  static const String income = 'in';
  static const String expense = 'out';

  static const List<String> all = [income, expense];

  static String getDescription(String type) {
    switch (type) {
      case income:
        return 'Ingreso';
      case expense:
        return 'Egreso';
      default:
        return type;
    }
  }
}
