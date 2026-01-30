/// Modelo para sesiones de caja
class CashSessionModel {
  final int? id;
  final int openedByUserId;
  final int openedAtMs;
  final double initialAmount;
  final int? closedAtMs;
  final int? closedByUserId;
  final String? note;

  CashSessionModel({
    this.id,
    required this.openedByUserId,
    required this.openedAtMs,
    this.initialAmount = 0.0,
    this.closedAtMs,
    this.closedByUserId,
    this.note,
  });

  DateTime get openedAt => DateTime.fromMillisecondsSinceEpoch(openedAtMs);
  DateTime? get closedAt => closedAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(closedAtMs!)
      : null;

  bool get isOpen => closedAtMs == null;
  bool get isClosed => closedAtMs != null;

  Duration get duration {
    final end = closedAt ?? DateTime.now();
    return end.difference(openedAt);
  }

  factory CashSessionModel.fromMap(Map<String, dynamic> map) {
    return CashSessionModel(
      id: map['id'] as int?,
      openedByUserId: map['opened_by_user_id'] as int,
      openedAtMs: map['opened_at_ms'] as int,
      initialAmount: (map['initial_amount'] as num?)?.toDouble() ?? 0.0,
      closedAtMs: map['closed_at_ms'] as int?,
      closedByUserId: map['closed_by_user_id'] as int?,
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'opened_by_user_id': openedByUserId,
      'opened_at_ms': openedAtMs,
      'initial_amount': initialAmount,
      'closed_at_ms': closedAtMs,
      'closed_by_user_id': closedByUserId,
      'note': note,
    };
  }

  CashSessionModel copyWith({
    int? id,
    int? openedByUserId,
    int? openedAtMs,
    double? initialAmount,
    int? closedAtMs,
    int? closedByUserId,
    String? note,
  }) {
    return CashSessionModel(
      id: id ?? this.id,
      openedByUserId: openedByUserId ?? this.openedByUserId,
      openedAtMs: openedAtMs ?? this.openedAtMs,
      initialAmount: initialAmount ?? this.initialAmount,
      closedAtMs: closedAtMs ?? this.closedAtMs,
      closedByUserId: closedByUserId ?? this.closedByUserId,
      note: note ?? this.note,
    );
  }
}
