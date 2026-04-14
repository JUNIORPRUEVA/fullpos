class CashTransactionType {
  CashTransactionType._();

  static const String sale = 'sale';
  static const String expense = 'expense';
  static const String withdrawal = 'withdrawal';
}

class CashTransactionModel {
  final int id;
  final String type;
  final double amount;
  final String description;
  final int createdAtMs;
  final int userId;
  final int cashSessionId;

  const CashTransactionModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAtMs,
    required this.userId,
    required this.cashSessionId,
  });

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'amount': amount,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'createdAtMs': createdAtMs,
      'userId': userId,
      'cashSessionId': cashSessionId,
    };
  }
}
