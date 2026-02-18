class CashboxDailyModel {
  final int? id;
  final String businessDate; // yyyy-MM-dd
  final int openedAtMs;
  final int openedByUserId;
  final double initialAmount;
  final String status; // OPEN/CLOSED
  final int? closedAtMs;
  final int? closedByUserId;
  final String? note;

  const CashboxDailyModel({
    this.id,
    required this.businessDate,
    required this.openedAtMs,
    required this.openedByUserId,
    required this.initialAmount,
    this.status = 'OPEN',
    this.closedAtMs,
    this.closedByUserId,
    this.note,
  });

  bool get isOpen => status == 'OPEN';
  bool get isClosed => status == 'CLOSED';

  DateTime get openedAt => DateTime.fromMillisecondsSinceEpoch(openedAtMs);
  DateTime? get closedAt =>
      closedAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(closedAtMs!);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'business_date': businessDate,
      'opened_at_ms': openedAtMs,
      'opened_by_user_id': openedByUserId,
      'initial_amount': initialAmount,
      'status': status,
      'closed_at_ms': closedAtMs,
      'closed_by_user_id': closedByUserId,
      'note': note,
    };
  }

  factory CashboxDailyModel.fromMap(Map<String, dynamic> map) {
    return CashboxDailyModel(
      id: map['id'] as int?,
      businessDate: map['business_date'] as String,
      openedAtMs: map['opened_at_ms'] as int,
      openedByUserId: map['opened_by_user_id'] as int,
      initialAmount: (map['initial_amount'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'OPEN',
      closedAtMs: map['closed_at_ms'] as int?,
      closedByUserId: map['closed_by_user_id'] as int?,
      note: map['note'] as String?,
    );
  }
}
