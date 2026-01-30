/// Modelo para devoluciones
class ReturnModel {
  final int? id;
  final int originalSaleId;
  final int returnSaleId;
  final String? note;
  final int createdAtMs;

  ReturnModel({
    this.id,
    required this.originalSaleId,
    required this.returnSaleId,
    this.note,
    required this.createdAtMs,
  });

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  factory ReturnModel.fromMap(Map<String, dynamic> map) {
    return ReturnModel(
      id: map['id'] as int?,
      originalSaleId: map['original_sale_id'] as int,
      returnSaleId: map['return_sale_id'] as int,
      note: map['note'] as String?,
      createdAtMs: map['created_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'original_sale_id': originalSaleId,
      'return_sale_id': returnSaleId,
      'note': note,
      'created_at_ms': createdAtMs,
    };
  }

  ReturnModel copyWith({
    int? id,
    int? originalSaleId,
    int? returnSaleId,
    String? note,
    int? createdAtMs,
  }) {
    return ReturnModel(
      id: id ?? this.id,
      originalSaleId: originalSaleId ?? this.originalSaleId,
      returnSaleId: returnSaleId ?? this.returnSaleId,
      note: note ?? this.note,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }
}
