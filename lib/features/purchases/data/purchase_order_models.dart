import 'package:flutter/foundation.dart';

@immutable
class PurchaseOrderModel {
  final int? id;
  final int supplierId;
  final String status; // PENDIENTE | RECIBIDA
  final double subtotal;
  final double taxRate; // porcentaje, ej 18.0
  final double taxAmount;
  final double total;
  final int isAuto; // 0/1
  final String? notes;
  final int createdAtMs;
  final int updatedAtMs;
  final int? receivedAtMs;
  final int? purchaseDateMs;

  const PurchaseOrderModel({
    this.id,
    required this.supplierId,
    required this.status,
    required this.subtotal,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    required this.isAuto,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.receivedAtMs,
    this.purchaseDateMs,
    this.notes,
  });

  factory PurchaseOrderModel.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderModel(
      id: map['id'] as int?,
      supplierId: map['supplier_id'] as int,
      status: (map['status'] as String?) ?? 'PENDIENTE',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (map['tax_amount'] as num?)?.toDouble() ?? 0.0,
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      isAuto: (map['is_auto'] as int?) ?? 0,
      notes: map['notes'] as String?,
      createdAtMs: (map['created_at_ms'] as int?) ?? 0,
      updatedAtMs: (map['updated_at_ms'] as int?) ?? 0,
      receivedAtMs: map['received_at_ms'] as int?,
      purchaseDateMs: map['purchase_date_ms'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'supplier_id': supplierId,
      'status': status,
      'subtotal': subtotal,
      'tax_rate': taxRate,
      'tax_amount': taxAmount,
      'total': total,
      'is_auto': isAuto,
      'notes': notes,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'received_at_ms': receivedAtMs,
      'purchase_date_ms': purchaseDateMs,
    };
  }

  PurchaseOrderModel copyWith({
    int? id,
    int? supplierId,
    String? status,
    double? subtotal,
    double? taxRate,
    double? taxAmount,
    double? total,
    int? isAuto,
    String? notes,
    int? createdAtMs,
    int? updatedAtMs,
    int? receivedAtMs,
    int? purchaseDateMs,
  }) {
    return PurchaseOrderModel(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      status: status ?? this.status,
      subtotal: subtotal ?? this.subtotal,
      taxRate: taxRate ?? this.taxRate,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      isAuto: isAuto ?? this.isAuto,
      notes: notes ?? this.notes,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      receivedAtMs: receivedAtMs ?? this.receivedAtMs,
      purchaseDateMs: purchaseDateMs ?? this.purchaseDateMs,
    );
  }
}

@immutable
class PurchaseOrderItemModel {
  final int? id;
  final int orderId;
  final int? productId;
  final String productCodeSnapshot;
  final String productNameSnapshot;
  final double qty;
  final double receivedQty;
  final double unitCost;
  final double totalLine;
  final int createdAtMs;

  const PurchaseOrderItemModel({
    this.id,
    required this.orderId,
    required this.productId,
    required this.productCodeSnapshot,
    required this.productNameSnapshot,
    required this.qty,
    required this.receivedQty,
    required this.unitCost,
    required this.totalLine,
    required this.createdAtMs,
  });

  factory PurchaseOrderItemModel.fromMap(Map<String, dynamic> map) {
    return PurchaseOrderItemModel(
      id: map['id'] as int?,
      orderId: map['order_id'] as int,
      productId: map['product_id'] as int?,
      productCodeSnapshot: (map['product_code_snapshot'] as String?) ?? '',
      productNameSnapshot: (map['product_name_snapshot'] as String?) ?? '',
      qty: (map['qty'] as num?)?.toDouble() ?? 0.0,
      receivedQty: (map['received_qty'] as num?)?.toDouble() ?? 0.0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0.0,
      totalLine: (map['total_line'] as num?)?.toDouble() ?? 0.0,
      createdAtMs: (map['created_at_ms'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'order_id': orderId,
      'product_id': productId,
      'product_code_snapshot': productCodeSnapshot,
      'product_name_snapshot': productNameSnapshot,
      'qty': qty,
      'received_qty': receivedQty,
      'unit_cost': unitCost,
      'total_line': totalLine,
      'created_at_ms': createdAtMs,
    };
  }
}

@immutable
class PurchaseOrderSummaryDto {
  final PurchaseOrderModel order;
  final String supplierName;

  const PurchaseOrderSummaryDto({
    required this.order,
    required this.supplierName,
  });
}

@immutable
class PurchaseOrderItemDetailDto {
  final PurchaseOrderItemModel item;
  final String productCode;
  final String productName;

  const PurchaseOrderItemDetailDto({
    required this.item,
    required this.productCode,
    required this.productName,
  });
}

@immutable
class PurchaseOrderDetailDto {
  final PurchaseOrderModel order;
  final String supplierName;
  final String? supplierPhone;
  final List<PurchaseOrderItemDetailDto> items;

  const PurchaseOrderDetailDto({
    required this.order,
    required this.supplierName,
    required this.supplierPhone,
    required this.items,
  });
}
