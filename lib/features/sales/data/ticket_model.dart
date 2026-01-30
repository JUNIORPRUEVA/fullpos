/// Modelo de Ticket guardado (carrito persistente)
class PosTicketModel {
  final int? id;
  final String ticketName;
  final int? userId;
  final int? clientId;
  final bool itbisEnabled;
  final double itbisRate;
  final double discountTotal;
  final int createdAtMs;
  final int updatedAtMs;

  PosTicketModel({
    this.id,
    required this.ticketName,
    this.userId,
    this.clientId,
    this.itbisEnabled = true,
    this.itbisRate = 0.18,
    this.discountTotal = 0,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'ticket_name': ticketName,
      'user_id': userId,
      'client_id': clientId,
      'itbis_enabled': itbisEnabled ? 1 : 0,
      'itbis_rate': itbisRate,
      'discount_total': discountTotal,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
    };
  }

  factory PosTicketModel.fromMap(Map<String, dynamic> map) {
    return PosTicketModel(
      id: map['id'] as int?,
      ticketName: map['ticket_name'] as String,
      userId: map['user_id'] as int?,
      clientId: map['client_id'] as int?,
      itbisEnabled: (map['itbis_enabled'] as int) == 1,
      itbisRate: (map['itbis_rate'] as num).toDouble(),
      discountTotal: (map['discount_total'] as num?)?.toDouble() ?? 0,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
    );
  }
}

/// Modelo de Item de Ticket
class PosTicketItemModel {
  final int? id;
  final int? ticketId;
  final int? productId;
  final String productCodeSnapshot;
  final String productNameSnapshot;
  final String description;
  final double qty;
  final double price;
  final double cost;
  final double discountLine;
  final double totalLine;

  PosTicketItemModel({
    this.id,
    this.ticketId,
    this.productId,
    required this.productCodeSnapshot,
    required this.productNameSnapshot,
    required this.description,
    required this.qty,
    required this.price,
    this.cost = 0,
    this.discountLine = 0,
    required this.totalLine,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'ticket_id': ticketId,
      'product_id': productId,
      'product_code_snapshot': productCodeSnapshot,
      'product_name_snapshot': productNameSnapshot,
      'description': description,
      'qty': qty,
      'price': price,
      'cost': cost,
      'discount_line': discountLine,
      'total_line': totalLine,
    };
  }

  factory PosTicketItemModel.fromMap(Map<String, dynamic> map) {
    return PosTicketItemModel(
      id: map['id'] as int?,
      ticketId: map['ticket_id'] as int,
      productId: map['product_id'] as int?,
      productCodeSnapshot: map['product_code_snapshot'] as String,
      productNameSnapshot: map['product_name_snapshot'] as String,
      description: map['description'] as String,
      qty: (map['qty'] as num).toDouble(),
      price: (map['price'] as num).toDouble(),
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
      discountLine: (map['discount_line'] as num?)?.toDouble() ?? 0,
      totalLine: (map['total_line'] as num).toDouble(),
    );
  }
}
