class SaleModel {
  final int? id;
  final String localCode;
  final String kind;
  final String status;
  final int? customerId;
  final String? customerNameSnapshot;
  final String? customerPhoneSnapshot;
  final String? customerRncSnapshot;
  final int itbisEnabled;
  final double itbisRate;
  final double discountTotal;
  final double subtotal;
  final double itbisAmount;
  final double total;
  final String? paymentMethod;
  final double paidAmount;
  final double changeAmount;
  final double creditInterestRate;
  final int? creditTermDays;
  final int? creditDueDateMs;
  final int? creditInstallments;
  final String? creditNote;
  final int fiscalEnabled;
  final String? ncfFull;
  final String? ncfType;
  final int? sessionId;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;

  SaleModel({
    this.id,
    required this.localCode,
    required this.kind,
    this.status = 'completed',
    this.customerId,
    this.customerNameSnapshot,
    this.customerPhoneSnapshot,
    this.customerRncSnapshot,
    this.itbisEnabled = 1,
    this.itbisRate = 0.18,
    this.discountTotal = 0.0,
    required this.subtotal,
    this.itbisAmount = 0.0,
    required this.total,
    this.paymentMethod,
    this.paidAmount = 0.0,
    this.changeAmount = 0.0,
    this.creditInterestRate = 0.0,
    this.creditTermDays,
    this.creditDueDateMs,
    this.creditInstallments,
    this.creditNote,
    this.fiscalEnabled = 0,
    this.ncfFull,
    this.ncfType,
    this.sessionId,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.deletedAtMs,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'local_code': localCode,
    'kind': kind,
    'status': status,
    'customer_id': customerId,
    'customer_name_snapshot': customerNameSnapshot,
    'customer_phone_snapshot': customerPhoneSnapshot,
    'customer_rnc_snapshot': customerRncSnapshot,
    'itbis_enabled': itbisEnabled,
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
    'fiscal_enabled': fiscalEnabled,
    'ncf_full': ncfFull,
    'ncf_type': ncfType,
    'session_id': sessionId,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
    'deleted_at_ms': deletedAtMs,
  };

  factory SaleModel.fromMap(Map<String, dynamic> map) => SaleModel(
    id: map['id'] as int?,
    localCode: map['local_code'] as String,
    kind: map['kind'] as String,
    status: map['status'] as String? ?? 'completed',
    customerId: map['customer_id'] as int?,
    customerNameSnapshot: map['customer_name_snapshot'] as String?,
    customerPhoneSnapshot: map['customer_phone_snapshot'] as String?,
    customerRncSnapshot: map['customer_rnc_snapshot'] as String?,
    itbisEnabled: map['itbis_enabled'] as int? ?? 1,
    itbisRate: (map['itbis_rate'] as num?)?.toDouble() ?? 0.18,
    discountTotal: (map['discount_total'] as num?)?.toDouble() ?? 0.0,
    subtotal: (map['subtotal'] as num).toDouble(),
    itbisAmount: (map['itbis_amount'] as num?)?.toDouble() ?? 0.0,
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
    fiscalEnabled: map['fiscal_enabled'] as int? ?? 0,
    ncfFull: map['ncf_full'] as String?,
    ncfType: map['ncf_type'] as String?,
    sessionId: map['session_id'] as int?,
    createdAtMs: map['created_at_ms'] as int,
    updatedAtMs: map['updated_at_ms'] as int,
    deletedAtMs: map['deleted_at_ms'] as int?,
  );

  SaleModel copyWith({
    int? id,
    String? localCode,
    String? kind,
    String? status,
    int? customerId,
    String? customerNameSnapshot,
    String? customerPhoneSnapshot,
    String? customerRncSnapshot,
    int? itbisEnabled,
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
    int? fiscalEnabled,
    String? ncfFull,
    String? ncfType,
    int? sessionId,
    int? createdAtMs,
    int? updatedAtMs,
    int? deletedAtMs,
  }) =>
      SaleModel(
        id: id ?? this.id,
        localCode: localCode ?? this.localCode,
        kind: kind ?? this.kind,
        status: status ?? this.status,
        customerId: customerId ?? this.customerId,
        customerNameSnapshot: customerNameSnapshot ?? this.customerNameSnapshot,
        customerPhoneSnapshot: customerPhoneSnapshot ?? this.customerPhoneSnapshot,
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
      );
}

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

  Map<String, dynamic> toMap() => {
    'id': id,
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

  factory SaleItemModel.fromMap(Map<String, dynamic> map) => SaleItemModel(
    id: map['id'] as int?,
    saleId: map['sale_id'] as int,
    productId: map['product_id'] as int?,
    productCodeSnapshot: map['product_code_snapshot'] as String,
    productNameSnapshot: map['product_name_snapshot'] as String,
    qty: (map['qty'] as num).toDouble(),
    unitPrice: (map['unit_price'] as num).toDouble(),
    purchasePriceSnapshot: (map['purchase_price_snapshot'] as num?)?.toDouble() ?? 0.0,
    discountLine: (map['discount_line'] as num?)?.toDouble() ?? 0.0,
    totalLine: (map['total_line'] as num).toDouble(),
    createdAtMs: map['created_at_ms'] as int,
  );
}

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

  Map<String, dynamic> toMap() => {
    'id': id,
    'original_sale_id': originalSaleId,
    'return_sale_id': returnSaleId,
    'note': note,
    'created_at_ms': createdAtMs,
  };

  factory ReturnModel.fromMap(Map<String, dynamic> map) => ReturnModel(
    id: map['id'] as int?,
    originalSaleId: map['original_sale_id'] as int,
    returnSaleId: map['return_sale_id'] as int,
    note: map['note'] as String?,
    createdAtMs: map['created_at_ms'] as int,
  );
}

class ReturnItemModel {
  final int? id;
  final int returnId;
  final int? saleItemId;
  final int? productId;
  final String description;
  final double qty;
  final double price;
  final double total;

  ReturnItemModel({
    this.id,
    required this.returnId,
    this.saleItemId,
    this.productId,
    required this.description,
    required this.qty,
    required this.price,
    required this.total,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'return_id': returnId,
    'sale_item_id': saleItemId,
    'product_id': productId,
    'description': description,
    'qty': qty,
    'price': price,
    'total': total,
  };

  factory ReturnItemModel.fromMap(Map<String, dynamic> map) => ReturnItemModel(
    id: map['id'] as int?,
    returnId: map['return_id'] as int,
    saleItemId: map['sale_item_id'] as int?,
    productId: map['product_id'] as int?,
    description: map['description'] as String,
    qty: (map['qty'] as num).toDouble(),
    price: (map['price'] as num).toDouble(),
    total: (map['total'] as num).toDouble(),
  );
}

class CreditPaymentModel {
  final int? id;
  final int saleId;
  final int clientId;
  final double amount;
  final String method;
  final String? note;
  final int createdAtMs;
  final int? userId;

  CreditPaymentModel({
    this.id,
    required this.saleId,
    required this.clientId,
    required this.amount,
    this.method = 'cash',
    this.note,
    required this.createdAtMs,
    this.userId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'sale_id': saleId,
    'client_id': clientId,
    'amount': amount,
    'method': method,
    'note': note,
    'created_at_ms': createdAtMs,
    'user_id': userId,
  };

  factory CreditPaymentModel.fromMap(Map<String, dynamic> map) => CreditPaymentModel(
    id: map['id'] as int?,
    saleId: map['sale_id'] as int,
    clientId: map['client_id'] as int,
    amount: (map['amount'] as num).toDouble(),
    method: map['method'] as String? ?? 'cash',
    note: map['note'] as String?,
    createdAtMs: map['created_at_ms'] as int,
    userId: map['user_id'] as int?,
  );
}
