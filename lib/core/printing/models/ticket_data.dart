/// Modelo de datos para un ticket
/// Modelo de datos para un ticket
/// Representa cualquier tipo de ticket (venta, cotización, devolución, etc.)
class TicketData {
  /// Número/código del ticket
  final String ticketNumber;

  /// Fecha y hora
  final DateTime dateTime;

  /// Nombre del cajero
  final String? cashierName;

  /// Información del cliente
  final ClientInfo? client;

  /// Items del ticket
  final List<TicketItemData> items;

  /// Subtotal antes de impuestos
  final double subtotal;

  /// Monto de descuento
  final double discount;

  /// Monto de ITBIS
  final double itbis;

  /// Porcentaje de ITBIS (0.18 = 18%)
  final double itbisRate;

  /// Total final
  final double total;

  /// Método de pago
  final String paymentMethod;

  /// Monto pagado
  final double paidAmount;

  /// Monto pendiente (apartados / pagos parciales)
  final double pendingAmount;

  /// Monto abonado en esta transacción
  final double lastPaymentAmount;

  /// Cambio/vuelto
  final double changeAmount;

  /// Datos de crédito (opcional)
  final double creditInterestRate;
  final int? creditTermDays;
  final int? creditInstallments;
  final DateTime? creditDueDate;
  final String? creditNote;

  /// Codigo de documento electronico
  final String? electronicInvoiceCode;

  /// Comprobante fiscal local/NCF (no e-CF).
  final String? fiscalReceiptNumber;
  final String? fiscalReceiptName;
  final String? fiscalReceiptCode;
  final DateTime? fiscalReceiptExpirationDate;

  /// Tipo de documento electronico/fiscal cuando aplica.
  final String? electronicDocumentType;

  /// Estado actual reportado para el documento electronico.
  final String? electronicDgiiStatus;

  /// Track id / identificador de seguimiento DGII.
  final String? electronicTrackId;

  /// Codigo devuelto por DGII cuando exista.
  final String? electronicDgiiCode;

  /// Mensaje devuelto por DGII cuando exista.
  final String? electronicDgiiMessage;

  /// Ambiente del documento electronico.
  final String? electronicEnvironment;

  /// Es una copia/reimpresión
  final bool isCopy;

  /// Leyenda extra (ej: "DEVOLUCIÓN", "CRÉDITO")
  final String? extraLegend;

  /// Estado legible (ej: PENDIENTE, PAGADO) usado para apartados
  final String? statusLabel;

  /// Marcador de apartado para renderizar bloques especiales
  final bool isLayaway;

  /// Tipo de documento
  final TicketType type;

  const TicketData({
    required this.ticketNumber,
    required this.dateTime,
    this.cashierName,
    this.client,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    required this.itbis,
    this.itbisRate = 0.18,
    required this.total,
    required this.paymentMethod,
    this.paidAmount = 0,
    this.pendingAmount = 0,
    this.lastPaymentAmount = 0,
    this.changeAmount = 0,
    this.creditInterestRate = 0,
    this.creditTermDays,
    this.creditInstallments,
    this.creditDueDate,
    this.creditNote,
    this.electronicInvoiceCode,
    this.fiscalReceiptNumber,
    this.fiscalReceiptName,
    this.fiscalReceiptCode,
    this.fiscalReceiptExpirationDate,
    this.electronicDocumentType,
    this.electronicDgiiStatus,
    this.electronicTrackId,
    this.electronicDgiiCode,
    this.electronicDgiiMessage,
    this.electronicEnvironment,
    this.isCopy = false,
    this.extraLegend,
    this.statusLabel,
    this.isLayaway = false,
    this.type = TicketType.sale,
  });

  /// Crear ticket de demostración
  factory TicketData.demo() {
    return TicketData(
      ticketNumber: 'DEMO-001',
      dateTime: DateTime.now(),
      cashierName: 'Cajero Demo',
      client: const ClientInfo(name: 'Cliente Demo', phone: '(809) 555-1234'),
      items: [
        const TicketItemData(
          name: 'Producto de Prueba',
          code: 'PROD-001',
          quantity: 2,
          unitPrice: 500.0,
          total: 1000.0,
        ),
      ],
      subtotal: 1000.0,
      itbis: 180.0,
      itbisRate: 0.18,
      total: 1180.0,
      paymentMethod: 'Efectivo',
      paidAmount: 1200.0,
      changeAmount: 20.0,
    );
  }

  /// Crear desde venta (SaleModel)
  factory TicketData.fromSale({
    required String localCode,
    required int createdAtMs,
    required double subtotal,
    required double total,
    required double itbisAmount,
    required double itbisRate,
    required String? paymentMethod,
    required double paidAmount,
    double pendingAmount = 0,
    double lastPaymentAmount = 0,
    String? statusLabel,
    bool isLayaway = false,
    required double changeAmount,
    required double discountTotal,
    String? electronicInvoiceCode,
    String? fiscalReceiptNumber,
    String? fiscalReceiptName,
    String? fiscalReceiptCode,
    DateTime? fiscalReceiptExpirationDate,
    String? electronicDocumentType,
    String? electronicDgiiStatus,
    String? electronicTrackId,
    String? electronicDgiiCode,
    String? electronicDgiiMessage,
    String? electronicEnvironment,
    String? customerName,
    String? customerPhone,
    String? customerRnc,
    String? cashierName,
    required List<TicketItemData> items,
    bool isCopy = false,
    double creditInterestRate = 0,
    int? creditTermDays,
    int? creditInstallments,
    DateTime? creditDueDate,
    String? creditNote,
  }) {
    return TicketData(
      ticketNumber: localCode,
      dateTime: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      cashierName: cashierName,
      client: customerName != null
          ? ClientInfo(
              name: customerName,
              phone: customerPhone,
              rnc: customerRnc,
            )
          : null,
      items: items,
      subtotal: subtotal,
      discount: discountTotal,
      itbis: itbisAmount,
      itbisRate: itbisRate,
      total: total,
      paymentMethod: _translatePaymentMethod(paymentMethod ?? 'cash'),
      paidAmount: paidAmount,
      pendingAmount: pendingAmount,
      lastPaymentAmount: lastPaymentAmount,
      changeAmount: changeAmount,
      creditInterestRate: creditInterestRate,
      creditTermDays: creditTermDays,
      creditInstallments: creditInstallments,
      creditDueDate: creditDueDate,
      creditNote: creditNote,
      electronicInvoiceCode: electronicInvoiceCode,
      fiscalReceiptNumber: fiscalReceiptNumber,
      fiscalReceiptName: fiscalReceiptName,
      fiscalReceiptCode: fiscalReceiptCode,
      fiscalReceiptExpirationDate: fiscalReceiptExpirationDate,
      electronicDocumentType: electronicDocumentType,
      electronicDgiiStatus: electronicDgiiStatus,
      electronicTrackId: electronicTrackId,
      electronicDgiiCode: electronicDgiiCode,
      electronicDgiiMessage: electronicDgiiMessage,
      electronicEnvironment: electronicEnvironment,
      isCopy: isCopy,
      statusLabel: statusLabel,
      isLayaway: isLayaway,
      type: TicketType.sale,
    );
  }

  static String _translatePaymentMethod(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'mixed':
        return 'Mixto';
      case 'credit':
        return 'Crédito';
      case 'layaway':
        return 'Apartado';
      default:
        return method;
    }
  }

  TicketData copyWith({
    String? ticketNumber,
    DateTime? dateTime,
    String? cashierName,
    ClientInfo? client,
    List<TicketItemData>? items,
    double? subtotal,
    double? discount,
    double? itbis,
    double? itbisRate,
    double? total,
    String? paymentMethod,
    double? paidAmount,
    double? pendingAmount,
    double? lastPaymentAmount,
    double? changeAmount,
    double? creditInterestRate,
    int? creditTermDays,
    int? creditInstallments,
    DateTime? creditDueDate,
    String? creditNote,
    String? electronicInvoiceCode,
    String? fiscalReceiptNumber,
    String? fiscalReceiptName,
    String? fiscalReceiptCode,
    DateTime? fiscalReceiptExpirationDate,
    String? electronicDocumentType,
    String? electronicDgiiStatus,
    String? electronicTrackId,
    String? electronicDgiiCode,
    String? electronicDgiiMessage,
    String? electronicEnvironment,
    bool? isCopy,
    String? extraLegend,
    String? statusLabel,
    bool? isLayaway,
    TicketType? type,
  }) {
    return TicketData(
      ticketNumber: ticketNumber ?? this.ticketNumber,
      dateTime: dateTime ?? this.dateTime,
      cashierName: cashierName ?? this.cashierName,
      client: client ?? this.client,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      itbis: itbis ?? this.itbis,
      itbisRate: itbisRate ?? this.itbisRate,
      total: total ?? this.total,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAmount: paidAmount ?? this.paidAmount,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      lastPaymentAmount: lastPaymentAmount ?? this.lastPaymentAmount,
      changeAmount: changeAmount ?? this.changeAmount,
      creditInterestRate: creditInterestRate ?? this.creditInterestRate,
      creditTermDays: creditTermDays ?? this.creditTermDays,
      creditInstallments: creditInstallments ?? this.creditInstallments,
      creditDueDate: creditDueDate ?? this.creditDueDate,
      creditNote: creditNote ?? this.creditNote,
      electronicInvoiceCode:
          electronicInvoiceCode ?? this.electronicInvoiceCode,
      fiscalReceiptNumber: fiscalReceiptNumber ?? this.fiscalReceiptNumber,
      fiscalReceiptName: fiscalReceiptName ?? this.fiscalReceiptName,
      fiscalReceiptCode: fiscalReceiptCode ?? this.fiscalReceiptCode,
      fiscalReceiptExpirationDate:
          fiscalReceiptExpirationDate ?? this.fiscalReceiptExpirationDate,
      electronicDocumentType:
          electronicDocumentType ?? this.electronicDocumentType,
      electronicDgiiStatus: electronicDgiiStatus ?? this.electronicDgiiStatus,
      electronicTrackId: electronicTrackId ?? this.electronicTrackId,
      electronicDgiiCode: electronicDgiiCode ?? this.electronicDgiiCode,
      electronicDgiiMessage:
          electronicDgiiMessage ?? this.electronicDgiiMessage,
      electronicEnvironment:
          electronicEnvironment ?? this.electronicEnvironment,
      isCopy: isCopy ?? this.isCopy,
      extraLegend: extraLegend ?? this.extraLegend,
      statusLabel: statusLabel ?? this.statusLabel,
      isLayaway: isLayaway ?? this.isLayaway,
      type: type ?? this.type,
    );
  }
}

/// Tipo de ticket
enum TicketType {
  sale, // Venta normal
  quote, // Cotización
  refund, // Devolución
  credit, // Nota de crédito
  copy, // Copia/Reimpresión
}

/// Información del cliente en ticket
class ClientInfo {
  final String name;
  final String? phone;
  final String? rnc;
  final String? email;
  final String? address;

  const ClientInfo({
    required this.name,
    this.phone,
    this.rnc,
    this.email,
    this.address,
  });
}

/// Item de un ticket
class TicketItemData {
  final String name;
  final String? code;
  final double quantity;
  final double unitPrice;
  final double total;
  final double? discount;

  const TicketItemData({
    required this.name,
    this.code,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.discount,
  });

  /// Crear desde item de venta
  factory TicketItemData.fromSaleItem({
    required String productName,
    String? productCode,
    required double qty,
    required double unitPrice,
    required double totalLine,
  }) {
    final cleanedName = _stripCodePrefix(name: productName, code: productCode);
    return TicketItemData(
      name: cleanedName,
      code: productCode,
      quantity: qty,
      unitPrice: unitPrice,
      total: totalLine,
    );
  }

  static String _stripCodePrefix({required String name, String? code}) {
    final rawName = name.trim();
    final rawCode = (code ?? '').trim();
    if (rawName.isEmpty) return rawName;
    if (rawCode.isEmpty) return rawName;

    // Caso común: "CODIGO - Descripción" o "CODIGO Descripción".
    final lowerName = rawName.toLowerCase();
    final lowerCode = rawCode.toLowerCase();
    if (!lowerName.startsWith(lowerCode)) return rawName;

    var rest = rawName.substring(rawCode.length).trimLeft();

    // Quitar separadores típicos después del código.
    while (rest.isNotEmpty) {
      final ch = rest[0];
      if (ch == '-' ||
          ch == '–' ||
          ch == '—' ||
          ch == ':' ||
          ch == '|' ||
          ch == '/') {
        rest = rest.substring(1).trimLeft();
        continue;
      }
      break;
    }

    return rest.isNotEmpty ? rest : rawName;
  }
}
