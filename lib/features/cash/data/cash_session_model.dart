/// Modelo de Sesión de Caja
class CashSessionModel {
  final int? id;
  final int userId;
  final String userName;
  final int openedAtMs;
  final double openingAmount;
  final int? cashboxDailyId;
  final String? businessDate; // yyyy-MM-dd
  final bool requiresClosure;
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
    this.cashboxDailyId,
    this.businessDate,
    this.requiresClosure = false,
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
  DateTime? get closedAt => closedAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(closedAtMs!)
      : null;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'opened_by_user_id': userId,
      'user_name': userName,
      'opened_at_ms': openedAtMs,
      'initial_amount': openingAmount,
      'cashbox_daily_id': cashboxDailyId,
      'business_date': businessDate,
      'requires_closure': requiresClosure ? 1 : 0,
      'closed_at_ms': closedAtMs,
      'closing_amount': closingAmount,
      'expected_cash': expectedCash,
      'difference': difference,
      'note': note,
      'status': status,
    };
  }

  factory CashSessionModel.fromMap(Map<String, dynamic> map) {
    final closedAtMs = map['closed_at_ms'] as int?;
    final rawStatus = (map['status'] as String?)?.trim();
    final normalizedStatus = rawStatus == null || rawStatus.isEmpty
        ? null
        : rawStatus.toUpperCase();
    final resolvedStatus = closedAtMs != null
        ? CashSessionStatus.closed
        : (normalizedStatus ?? CashSessionStatus.open);

    return CashSessionModel(
      id: map['id'] as int?,
      userId: map['opened_by_user_id'] as int? ?? 1,
      userName: map['user_name'] as String? ?? 'admin',
      openedAtMs: map['opened_at_ms'] as int,
      openingAmount: (map['initial_amount'] as num?)?.toDouble() ?? 0.0,
      cashboxDailyId: map['cashbox_daily_id'] as int?,
      businessDate: map['business_date'] as String?,
      requiresClosure: (map['requires_closure'] as int? ?? 0) == 1,
      closedAtMs: closedAtMs,
      closingAmount: (map['closing_amount'] as num?)?.toDouble(),
      expectedCash: (map['expected_cash'] as num?)?.toDouble(),
      difference: (map['difference'] as num?)?.toDouble(),
      note: map['note'] as String?,
      status: resolvedStatus,
    );
  }

  CashSessionModel copyWith({
    int? id,
    int? userId,
    String? userName,
    int? openedAtMs,
    double? openingAmount,
    int? cashboxDailyId,
    String? businessDate,
    bool? requiresClosure,
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
      cashboxDailyId: cashboxDailyId ?? this.cashboxDailyId,
      businessDate: businessDate ?? this.businessDate,
      requiresClosure: requiresClosure ?? this.requiresClosure,
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
