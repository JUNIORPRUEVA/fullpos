/// Modelo para items/líneas de venta
class SaleItemModel {
  final int? id;
  final int saleId;
  final int? productId;
  final String productCodeSnapshot;
  final String productNameSnapshot;
  final double qty;
  final double unitPrice;
  final double purchasePriceSnapshot;
  final double discountLine;
  final double totalLine;
  final int createdAtMs;

  SaleItemModel({
    this.id,
    required this.saleId,
    this.productId,
    required this.productCodeSnapshot,
    required this.productNameSnapshot,
    required this.qty,
    required this.unitPrice,
    this.purchasePriceSnapshot = 0.0,
    this.discountLine = 0.0,
    required this.totalLine,
    required this.createdAtMs,
  });

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  /// Subtotal antes de descuento
  double get subtotalLine => qty * unitPrice;

  /// Ganancia por línea
  double get profitLine => (unitPrice - purchasePriceSnapshot) * qty - discountLine;

  factory SaleItemModel.fromMap(Map<String, dynamic> map) {
    return SaleItemModel(
      id: map['id'] as int?,
      saleId: map['sale_id'] as int,
      productId: map['product_id'] as int?,
      productCodeSnapshot: map['product_code_snapshot'] as String,
      productNameSnapshot: map['product_name_snapshot'] as String,
      qty: (map['qty'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      purchasePriceSnapshot:
          (map['purchase_price_snapshot'] as num?)?.toDouble() ?? 0.0,
      discountLine: (map['discount_line'] as num?)?.toDouble() ?? 0.0,
      totalLine: (map['total_line'] as num).toDouble(),
      createdAtMs: map['created_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'product_code_snapshot': productCodeSnapshot,
      'product_name_snapshot': productNameSnapshot,
      'qty': qty,
      'unit_price': unitPrice,
      'purchase_price_snapshot': purchasePriceSnapshot,
      'discount_line': discountLine,
      'total_line': totalLine,
      'created_at_ms': createdAtMs,
    };
  }

  SaleItemModel copyWith({
    int? id,
    int? saleId,
    int? productId,
    String? productCodeSnapshot,
    String? productNameSnapshot,
    double? qty,
    double? unitPrice,
    double? purchasePriceSnapshot,
    double? discountLine,
    double? totalLine,
    int? createdAtMs,
  }) {
    return SaleItemModel(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      productId: productId ?? this.productId,
      productCodeSnapshot: productCodeSnapshot ?? this.productCodeSnapshot,
      productNameSnapshot: productNameSnapshot ?? this.productNameSnapshot,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      purchasePriceSnapshot:
          purchasePriceSnapshot ?? this.purchasePriceSnapshot,
      discountLine: discountLine ?? this.discountLine,
      totalLine: totalLine ?? this.totalLine,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }
}
