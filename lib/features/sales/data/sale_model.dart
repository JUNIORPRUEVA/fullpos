import 'sale_item_model.dart';

/// Modelo para ventas/facturas/cotizaciones
class SaleModel {
  final int? id;
  final String localCode;
  final String kind; // 'invoice' | 'quote' | 'return'
  final String status; // 'draft' | 'completed' | 'cancelled'
  final int? customerId;
  final String? customerNameSnapshot;
  final String? customerPhoneSnapshot;
  final String? customerRncSnapshot;
  final bool itbisEnabled;
  final double itbisRate;
  final double discountTotal;
  final double subtotal;
  final double itbisAmount;
  final double total;
  final String? paymentMethod; // 'cash' | 'transfer' | 'card' | 'mixed'
  final double paidAmount;
  final double changeAmount;
  final double creditInterestRate;
  final int? creditTermDays;
  final int? creditDueDateMs;
  final int? creditInstallments;
  final String? creditNote;
  final bool fiscalEnabled;
  final String? ncfFull;
  final String? ncfType;
  final int? sessionId;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;

  // Items no se guardan en la tabla sales, pero se cargan por relación
  List<SaleItemModel>? items;

  SaleModel({
    this.id,
    required this.localCode,
    required this.kind,
    this.status = 'completed',
    this.customerId,
    this.customerNameSnapshot,
    this.customerPhoneSnapshot,
    this.customerRncSnapshot,
    this.itbisEnabled = true,
    this.itbisRate = 0.18,
    this.discountTotal = 0.0,
    required this.subtotal,
    required this.itbisAmount,
    required this.total,
    this.paymentMethod,
    this.paidAmount = 0.0,
    this.changeAmount = 0.0,
    this.creditInterestRate = 0.0,
    this.creditTermDays,
    this.creditDueDateMs,
    this.creditInstallments,
    this.creditNote,
    this.fiscalEnabled = false,
    this.ncfFull,
    this.ncfType,
    this.sessionId,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.deletedAtMs,
    this.items,
  });

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  DateTime? get deletedAt => deletedAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(deletedAtMs!)
      : null;
  DateTime? get creditDueDate => creditDueDateMs != null
      ? DateTime.fromMillisecondsSinceEpoch(creditDueDateMs!)
      : null;

  bool get isDeleted => deletedAtMs != null;
  bool get isInvoice => kind == SaleKind.invoice;
  bool get isQuote => kind == SaleKind.quote;
  bool get isReturn => kind == SaleKind.returnSale;
  bool get isCompleted => status == SaleStatus.completed;
  bool get isDraft => status == SaleStatus.draft;
  bool get isCancelled => status == SaleStatus.cancelled;

  /// Ganancia total estimada
  double get profit {
    if (items == null || items!.isEmpty) return 0.0;
    return items!.fold<double>(0.0, (sum, item) => sum + item.profitLine);
  }

  factory SaleModel.fromMap(Map<String, dynamic> map) {
    return SaleModel(
      id: map['id'] as int?,
      localCode: map['local_code'] as String,
      kind: map['kind'] as String,
      status: map['status'] as String? ?? 'completed',
      customerId: map['customer_id'] as int?,
      customerNameSnapshot: map['customer_name_snapshot'] as String?,
      customerPhoneSnapshot: map['customer_phone_snapshot'] as String?,
      customerRncSnapshot: map['customer_rnc_snapshot'] as String?,
      itbisEnabled: (map['itbis_enabled'] as int) == 1,
      itbisRate: (map['itbis_rate'] as num).toDouble(),
      discountTotal: (map['discount_total'] as num?)?.toDouble() ?? 0.0,
      subtotal: (map['subtotal'] as num).toDouble(),
      itbisAmount: (map['itbis_amount'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      paymentMethod: map['payment_method'] as String?,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      changeAmount: (map['change_amount'] as num?)?.toDouble() ?? 0.0,
      creditInterestRate:
          (map['credit_interest_rate'] as num?)?.toDouble() ?? 0.0,
      creditTermDays: map['credit_term_days'] as int?,
      creditDueDateMs: map['credit_due_date_ms'] as int?,
      creditInstallments: map['credit_installments'] as int?,
      creditNote: map['credit_note'] as String?,
      fiscalEnabled: (map['fiscal_enabled'] as int) == 1,
      ncfFull: map['ncf_full'] as String?,
      ncfType: map['ncf_type'] as String?,
      sessionId: map['session_id'] as int?,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
      deletedAtMs: map['deleted_at_ms'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'local_code': localCode,
      'kind': kind,
      'status': status,
      'customer_id': customerId,
      'customer_name_snapshot': customerNameSnapshot,
      'customer_phone_snapshot': customerPhoneSnapshot,
      'customer_rnc_snapshot': customerRncSnapshot,
      'itbis_enabled': itbisEnabled ? 1 : 0,
      'itbis_rate': itbisRate,
      'discount_total': discountTotal,
      'subtotal': subtotal,
      'itbis_amount': itbisAmount,
      'total': total,
      'payment_method': paymentMethod,
      'paid_amount': paidAmount,
      'change_amount': changeAmount,
      'credit_interest_rate': creditInterestRate,
      'credit_term_days': creditTermDays,
      'credit_due_date_ms': creditDueDateMs,
      'credit_installments': creditInstallments,
      'credit_note': creditNote,
      'fiscal_enabled': fiscalEnabled ? 1 : 0,
      'ncf_full': ncfFull,
      'ncf_type': ncfType,
      'session_id': sessionId,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'deleted_at_ms': deletedAtMs,
    };
  }

  SaleModel copyWith({
    int? id,
    String? localCode,
    String? kind,
    String? status,
    int? customerId,
    String? customerNameSnapshot,
    String? customerPhoneSnapshot,
    String? customerRncSnapshot,
    bool? itbisEnabled,
    double? itbisRate,
    double? discountTotal,
    double? subtotal,
    double? itbisAmount,
    double? total,
    String? paymentMethod,
    double? paidAmount,
    double? changeAmount,
    double? creditInterestRate,
    int? creditTermDays,
    int? creditDueDateMs,
    int? creditInstallments,
    String? creditNote,
    bool? fiscalEnabled,
    String? ncfFull,
    String? ncfType,
    int? sessionId,
    int? createdAtMs,
    int? updatedAtMs,
    int? deletedAtMs,
    List<SaleItemModel>? items,
  }) {
    return SaleModel(
      id: id ?? this.id,
      localCode: localCode ?? this.localCode,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      customerId: customerId ?? this.customerId,
      customerNameSnapshot: customerNameSnapshot ?? this.customerNameSnapshot,
      customerPhoneSnapshot:
          customerPhoneSnapshot ?? this.customerPhoneSnapshot,
      customerRncSnapshot: customerRncSnapshot ?? this.customerRncSnapshot,
      itbisEnabled: itbisEnabled ?? this.itbisEnabled,
      itbisRate: itbisRate ?? this.itbisRate,
      discountTotal: discountTotal ?? this.discountTotal,
      subtotal: subtotal ?? this.subtotal,
      itbisAmount: itbisAmount ?? this.itbisAmount,
      total: total ?? this.total,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAmount: paidAmount ?? this.paidAmount,
      changeAmount: changeAmount ?? this.changeAmount,
      creditInterestRate: creditInterestRate ?? this.creditInterestRate,
      creditTermDays: creditTermDays ?? this.creditTermDays,
      creditDueDateMs: creditDueDateMs ?? this.creditDueDateMs,
      creditInstallments: creditInstallments ?? this.creditInstallments,
      creditNote: creditNote ?? this.creditNote,
      fiscalEnabled: fiscalEnabled ?? this.fiscalEnabled,
      ncfFull: ncfFull ?? this.ncfFull,
      ncfType: ncfType ?? this.ncfType,
      sessionId: sessionId ?? this.sessionId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
      items: items ?? this.items,
    );
  }
}

/// Tipos de venta
class SaleKind {
  static const String invoice = 'invoice';
  static const String quote = 'quote';
  static const String returnSale = 'return';

  static const List<String> all = [invoice, quote, returnSale];

  static String getDescription(String kind) {
    switch (kind) {
      case invoice:
        return 'Factura';
      case quote:
        return 'Cotización';
      case returnSale:
        return 'Devolución';
      default:
        return kind;
    }
  }
}

/// Estados de venta
class SaleStatus {
  static const String draft = 'draft';
  static const String completed = 'completed';
  static const String cancelled = 'cancelled';

  static const List<String> all = [draft, completed, cancelled];

  static String getDescription(String status) {
    switch (status) {
      case draft:
        return 'Borrador';
      case completed:
        return 'Completado';
      case cancelled:
        return 'Cancelado';
      default:
        return status;
    }
  }
}

/// Métodos de pago
class PaymentMethod {
  static const String cash = 'cash';
  static const String transfer = 'transfer';
  static const String card = 'card';
  static const String mixed = 'mixed';
  static const String credit = 'credit';
  static const String layaway = 'layaway';

  static const List<String> all = [
    cash,
    transfer,
    card,
    mixed,
    credit,
    layaway,
  ];

  static String getDescription(String method) {
    switch (method) {
      case cash:
        return 'Efectivo';
      case transfer:
        return 'Transferencia';
      case card:
        return 'Tarjeta';
      case mixed:
        return 'Mixto';
      case credit:
        return 'Crédito';
      case layaway:
        return 'Apartado';
      default:
        return method;
    }
  }
}
