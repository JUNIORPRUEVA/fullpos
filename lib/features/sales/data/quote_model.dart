/// Modelo de Cotización
class QuoteModel {
  final int? id;
  final int clientId;
  final int? userId;
  final String? ticketName;
  final double subtotal;
  final bool itbisEnabled;
  final double itbisRate;
  final double itbisAmount;
  final double discountTotal;
  final double total;
  final String status; // 'OPEN', 'SENT', 'CONVERTED', 'CANCELLED'
  final String? notes;
  final int createdAtMs;
  final int updatedAtMs;

  QuoteModel({
    this.id,
    required this.clientId,
    this.userId,
    this.ticketName,
    required this.subtotal,
    this.itbisEnabled = true,
    this.itbisRate = 0.18,
    this.itbisAmount = 0,
    this.discountTotal = 0,
    required this.total,
    this.status = 'OPEN',
    this.notes,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'client_id': clientId,
      'user_id': userId,
      'ticket_name': ticketName,
      'subtotal': subtotal,
      'itbis_enabled': itbisEnabled ? 1 : 0,
      'itbis_rate': itbisRate,
      'itbis_amount': itbisAmount,
      'discount_total': discountTotal,
      'total': total,
      'status': status,
      'notes': notes,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
    };
  }

  factory QuoteModel.fromMap(Map<String, dynamic> map) {
    return QuoteModel(
      id: map['id'] as int?,
      clientId: map['client_id'] as int,
      userId: map['user_id'] as int?,
      ticketName: map['ticket_name'] as String?,
      subtotal: (map['subtotal'] as num).toDouble(),
      itbisEnabled: (map['itbis_enabled'] as int) == 1,
      itbisRate: (map['itbis_rate'] as num).toDouble(),
      itbisAmount: (map['itbis_amount'] as num).toDouble(),
      discountTotal: (map['discount_total'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      status: map['status'] as String,
      notes: map['notes'] as String?,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
    );
  }
}

/// Modelo de Item de Cotización
class QuoteItemModel {
  final int? id;
  final int quoteId;
  final int? productId;
  final String? productCode;
  final String productName;
  final String description;
  final double qty;
  final double price;
  final double unitPrice;
  final double cost;
  final double purchasePrice;
  final double discountLine;
  final double totalLine;

  QuoteItemModel({
    this.id,
    required this.quoteId,
    this.productId,
    this.productCode,
    required this.productName,
    required this.description,
    required this.qty,
    required this.price,
    double? unitPrice,
    this.cost = 0,
    this.purchasePrice = 0,
    this.discountLine = 0,
    required this.totalLine,
  }) : unitPrice = unitPrice ?? price;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'quote_id': quoteId,
      'product_id': productId,
      'product_code_snapshot': productCode,
      'product_name_snapshot': productName,
      'description': description,
      'qty': qty,
      'unit_price': unitPrice,
      'price': price,
      'cost': cost,
      'discount_line': discountLine,
      'total_line': totalLine,
    };
  }

  factory QuoteItemModel.fromMap(Map<String, dynamic> map) {
    final rawPrice = map['price'] ?? map['unit_price'] ?? 0;
    final rawUnitPrice = map['unit_price'] ?? map['price'] ?? 0;
    return QuoteItemModel(
      id: map['id'] as int?,
      quoteId: map['quote_id'] as int,
      productId: map['product_id'] as int?,
      productCode: map['product_code_snapshot'] as String?,
      productName: map['product_name_snapshot'] as String? ?? 'N/A',
      description: map['description'] as String,
      qty: (map['qty'] as num).toDouble(),
      price: (rawPrice as num).toDouble(),
      unitPrice: (rawUnitPrice as num).toDouble(),
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
      purchasePrice: (map['purchase_price'] as num?)?.toDouble() ?? 0,
      discountLine: (map['discount_line'] as num?)?.toDouble() ?? 0,
      totalLine: (map['total_line'] as num).toDouble(),
    );
  }
}

/// DTO para cotización completa con cliente e items
class QuoteDetailDto {
  final QuoteModel quote;
  final String clientName;
  final String? clientPhone;
  final String? clientRnc;
  final List<QuoteItemModel> items;

  QuoteDetailDto({
    required this.quote,
    required this.clientName,
    this.clientPhone,
    this.clientRnc,
    required this.items,
  });
}
