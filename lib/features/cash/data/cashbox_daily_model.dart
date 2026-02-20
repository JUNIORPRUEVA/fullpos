class CashboxDailyModel {
  final int? id;
  final String businessDate; // yyyy-MM-dd
  final int openedAtMs;
  final int openedByUserId;
  final double initialAmount;
  final double currentAmount;
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
    required this.currentAmount,
    this.status = 'OPEN',
    this.closedAtMs,
    this.closedByUserId,
    this.note,
  });

  bool get isOpen => status == 'OPEN';
  bool get isClosed => status == 'CLOSED';

  DateTime get openedAt => DateTime.fromMillisecondsSinceEpoch(openedAtMs);
  DateTime? get closedAt => closedAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(closedAtMs!);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'business_date': businessDate,
      'opened_at_ms': openedAtMs,
      'opened_by_user_id': openedByUserId,
      'initial_amount': initialAmount,
      'current_amount': currentAmount,
      'status': status,
      'closed_at_ms': closedAtMs,
      'closed_by_user_id': closedByUserId,
      'note': note,
    };
  }

  factory CashboxDailyModel.fromMap(Map<String, dynamic> map) {
    final initial = (map['initial_amount'] as num?)?.toDouble() ?? 0;
    final current = (map['current_amount'] as num?)?.toDouble();
    return CashboxDailyModel(
      id: map['id'] as int?,
      businessDate: map['business_date'] as String,
      openedAtMs: map['opened_at_ms'] as int,
      openedByUserId: map['opened_by_user_id'] as int,
      initialAmount: initial,
      currentAmount: current ?? initial,
      status: map['status'] as String? ?? 'OPEN',
      closedAtMs: map['closed_at_ms'] as int?,
      closedByUserId: map['closed_by_user_id'] as int?,
      note: map['note'] as String?,
    );
  }
}
