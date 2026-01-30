/// Modelo de Sesión de Caja
class CashSessionModel {
  final int? id;
  final int userId;
  final String userName;
  final int openedAtMs;
  final double openingAmount;
  final int? closedAtMs;
  final double? closingAmount;
  final double? expectedCash;
  final double? difference;
  final String? note;
  final String status; // OPEN / CLOSED

  CashSessionModel({
    this.id,
    required this.userId,
    required this.userName,
    required this.openedAtMs,
    required this.openingAmount,
    this.closedAtMs,
    this.closingAmount,
    this.expectedCash,
    this.difference,
    this.note,
    this.status = 'OPEN',
  });

  bool get isOpen => status == 'OPEN';
  bool get isClosed => status == 'CLOSED';

  DateTime get openedAt => DateTime.fromMillisecondsSinceEpoch(openedAtMs);
  DateTime? get closedAt =>
      closedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(closedAtMs!) : null;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'opened_by_user_id': userId,
      'user_name': userName,
      'opened_at_ms': openedAtMs,
      'initial_amount': openingAmount,
      'closed_at_ms': closedAtMs,
      'closing_amount': closingAmount,
      'expected_cash': expectedCash,
      'difference': difference,
      'note': note,
      'status': status,
    };
  }

  factory CashSessionModel.fromMap(Map<String, dynamic> map) {
    return CashSessionModel(
      id: map['id'] as int?,
      userId: map['opened_by_user_id'] as int? ?? 1,
      userName: map['user_name'] as String? ?? 'admin',
      openedAtMs: map['opened_at_ms'] as int,
      openingAmount: (map['initial_amount'] as num?)?.toDouble() ?? 0.0,
      closedAtMs: map['closed_at_ms'] as int?,
      closingAmount: (map['closing_amount'] as num?)?.toDouble(),
      expectedCash: (map['expected_cash'] as num?)?.toDouble(),
      difference: (map['difference'] as num?)?.toDouble(),
      note: map['note'] as String?,
      status: map['status'] as String? ?? 
          (map['closed_at_ms'] != null ? 'CLOSED' : 'OPEN'),
    );
  }

  CashSessionModel copyWith({
    int? id,
    int? userId,
    String? userName,
    int? openedAtMs,
    double? openingAmount,
    int? closedAtMs,
    double? closingAmount,
    double? expectedCash,
    double? difference,
    String? note,
    String? status,
  }) {
    return CashSessionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      openedAtMs: openedAtMs ?? this.openedAtMs,
      openingAmount: openingAmount ?? this.openingAmount,
      closedAtMs: closedAtMs ?? this.closedAtMs,
      closingAmount: closingAmount ?? this.closingAmount,
      expectedCash: expectedCash ?? this.expectedCash,
      difference: difference ?? this.difference,
      note: note ?? this.note,
      status: status ?? this.status,
    );
  }
}

/// Constantes para estados de sesión
class CashSessionStatus {
  CashSessionStatus._();
  static const String open = 'OPEN';
  static const String closed = 'CLOSED';
}
