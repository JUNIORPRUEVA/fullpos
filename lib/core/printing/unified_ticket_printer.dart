import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'models/models.dart';
import '../../features/settings/data/printer_settings_model.dart';
import '../../features/settings/data/printer_settings_repository.dart';
import '../../features/sales/data/sales_model.dart';
import 'thermal_printer_service.dart';

/// Servicio unificado de impresión de tickets
/// Este servicio es el punto único para imprimir cualquier tipo de ticket
class UnifiedTicketPrinter {
  UnifiedTicketPrinter._();

  // ============================================================
  // MÉTODO PRINCIPAL: Imprimir cualquier ticket
  // ============================================================

  /// Imprime un ticket usando la configuración centralizada
  /// Este es el método principal que debe usarse en toda la app
  static Future<PrintTicketResult> printTicket({
    required TicketData data,
    int? overrideCopies,
  }) async {
    try {
      // 1. Obtener datos de empresa (FUENTE ÚNICA)
      final company = await CompanyInfoRepository.getCurrentCompanyInfo();
      debugPrint('📋 Empresa: ${company.name}');

      // 2. Obtener configuración de impresora
      final printerSettings = await PrinterSettingsRepository.getOrCreate();

      // 3. Crear configuración de layout desde settings
      final layout = TicketLayoutConfig.fromPrinterSettings(printerSettings);

      // 4. Crear builder con datos centralizados
      final builder = TicketBuilder(layout: layout, company: company);

      // 5. Generar PDF
      final pdf = builder.buildPdf(data);

      // 6. Imprimir
      final copies = overrideCopies ?? printerSettings.copies;
      final result = await ThermalPrinterService.printDocument(
        document: pdf,
        settings: printerSettings,
        overrideCopies: copies,
      );

      if (result.success) {
        debugPrint('✅ Ticket impreso: ${data.ticketNumber}');
      } else {
        debugPrint('❌ Error imprimiendo: ${result.message}');
      }

      return PrintTicketResult(
        success: result.success,
        message: result.message,
        ticketNumber: data.ticketNumber,
      );
    } catch (e) {
      debugPrint('❌ Error en printTicket: $e');
      return PrintTicketResult(
        success: false,
        message: 'Error de impresión: $e',
        ticketNumber: data.ticketNumber,
      );
    }
  }

  /// Imprime un ticket usando una lista de lineas ya alineadas.
  static Future<PrintTicketResult> printCustomLines({
    required List<String> lines,
    required String ticketNumber,
    bool includeLogo = true,
    int? overrideCopies,
  }) async {
    try {
      final company = await CompanyInfoRepository.getCurrentCompanyInfo();
      final printerSettings = await PrinterSettingsRepository.getOrCreate();
      final layout = TicketLayoutConfig.fromPrinterSettings(printerSettings);

      final builder = TicketBuilder(layout: layout, company: company);
      final pdf = builder.buildPdfFromLines(lines, includeLogo: includeLogo);

      final copies = overrideCopies ?? printerSettings.copies;
      final result = await ThermalPrinterService.printDocument(
        document: pdf,
        settings: printerSettings,
        overrideCopies: copies,
      );

      return PrintTicketResult(
        success: result.success,
        message: result.message,
        ticketNumber: ticketNumber,
      );
    } catch (e) {
      return PrintTicketResult(
        success: false,
        message: 'Error de impresion: $e',
        ticketNumber: ticketNumber,
      );
    }
  }

  // ============================================================
  // MÉTODOS DE CONVENIENCIA PARA VENTAS
  // ============================================================

  /// Imprime un ticket de venta (desde SaleModel)
  static Future<PrintTicketResult> printSaleTicket({
    required SaleModel sale,
    required List<SaleItemModel> items,
    String? cashierName,
    int? overrideCopies,
    double? pendingAmount,
    double? lastPaymentAmount,
    String? statusLabel,
    bool isLayaway = false,
  }) async {
    // Convertir items a TicketItemData
    final ticketItems = items
        .map(
          (item) => TicketItemData.fromSaleItem(
            productName: item.productNameSnapshot,
            productCode: null,
            qty: item.qty,
            unitPrice: item.unitPrice,
            totalLine: item.totalLine,
          ),
        )
        .toList();

    // Normalizar datos de crédito para que el ticket muestre PENDIENTE
    final isCredit = (sale.paymentMethod?.toLowerCase() ?? '') == 'credit';
    final normalizedPaid = sale.paidAmount;
    final normalizedChange = isCredit ? 0.0 : sale.changeAmount;
    final normalizedPending = pendingAmount ??
      (sale.total - normalizedPaid).clamp(0, double.infinity);
    final normalizedStatus = statusLabel ?? (isCredit ? 'PENDIENTE' : sale.status);

    // Crear TicketData desde la venta
    final ticketData = TicketData.fromSale(
      localCode: sale.localCode,
      createdAtMs: sale.createdAtMs,
      subtotal: sale.subtotal,
      total: sale.total,
      itbisAmount: sale.itbisAmount,
      itbisRate: sale.itbisRate,
      paymentMethod: sale.paymentMethod,
      paidAmount: normalizedPaid,
      pendingAmount: normalizedPending,
      lastPaymentAmount: lastPaymentAmount ?? 0,
      statusLabel: normalizedStatus,
      isLayaway: isLayaway,
      changeAmount: normalizedChange,
      discountTotal: sale.discountTotal,
      ncfFull: sale.ncfFull,
      customerName: sale.customerNameSnapshot,
      customerPhone: sale.customerPhoneSnapshot,
      customerRnc: sale.customerRncSnapshot,
      cashierName: cashierName,
      items: ticketItems,
      creditInterestRate: sale.creditInterestRate,
      creditTermDays: sale.creditTermDays,
      creditInstallments: sale.creditInstallments,
      creditDueDate: sale.creditDueDateMs != null
        ? DateTime.fromMillisecondsSinceEpoch(sale.creditDueDateMs!)
        : null,
      creditNote: sale.creditNote,
    );

    return await printTicket(data: ticketData, overrideCopies: overrideCopies);
  }

  /// Imprime automáticamente si está habilitado en configuración
  static Future<PrintTicketResult> autoPrintSale({
    required SaleModel sale,
    required List<SaleItemModel> items,
    String? cashierName,
  }) async {
    try {
      final settings = await PrinterSettingsRepository.getOrCreate();

      if (settings.autoPrintOnPayment != 1) {
        debugPrint('ℹ️ Auto-print desactivado');
        return PrintTicketResult(
          success: true,
          message: 'Auto-print desactivado',
          ticketNumber: sale.localCode,
          skipped: true,
        );
      }

      return await printSaleTicket(
        sale: sale,
        items: items,
        cashierName: cashierName,
      );
    } catch (e) {
      return PrintTicketResult(
        success: false,
        message: 'Error: $e',
        ticketNumber: sale.localCode,
      );
    }
  }

  /// Reimprime una venta (ignora autoPrintOnPayment)
  static Future<PrintTicketResult> reprintSale({
    required SaleModel sale,
    required List<SaleItemModel> items,
    String? cashierName,
    int? copies,
  }) async {
    // Convertir items
    final ticketItems = items
        .map(
          (item) => TicketItemData.fromSaleItem(
            productName: item.productNameSnapshot,
            productCode: null,
            qty: item.qty,
            unitPrice: item.unitPrice,
            totalLine: item.totalLine,
          ),
        )
        .toList();

    // Crear TicketData marcado como copia
    final ticketData = TicketData.fromSale(
      localCode: sale.localCode,
      createdAtMs: sale.createdAtMs,
      subtotal: sale.subtotal,
      total: sale.total,
      itbisAmount: sale.itbisAmount,
      itbisRate: sale.itbisRate,
      paymentMethod: sale.paymentMethod,
      paidAmount: sale.paidAmount,
      changeAmount: sale.changeAmount,
      discountTotal: sale.discountTotal,
      ncfFull: sale.ncfFull,
      customerName: sale.customerNameSnapshot,
      customerPhone: sale.customerPhoneSnapshot,
      customerRnc: sale.customerRncSnapshot,
      cashierName: cashierName,
      items: ticketItems,
      creditInterestRate: sale.creditInterestRate,
      creditTermDays: sale.creditTermDays,
      creditInstallments: sale.creditInstallments,
      creditDueDate: sale.creditDueDateMs != null
          ? DateTime.fromMillisecondsSinceEpoch(sale.creditDueDateMs!)
          : null,
      creditNote: sale.creditNote,
      isCopy: true,
    );

    return await printTicket(data: ticketData, overrideCopies: copies ?? 1);
  }

  // ============================================================
  // TICKET DE PRUEBA
  // ============================================================

  /// Imprime un ticket de prueba con datos demo
  static Future<PrintTicketResult> printTestTicket() async {
    final demoData = TicketData.demo();
    return await printTicket(data: demoData, overrideCopies: 1);
  }

  /// Intenta abrir la caja registradora enviando un trabajo mínimo a la
  /// impresora de tickets configurada.
  static Future<PrintTicketResult> openCashDrawerPulse() async {
    try {
      final company = await CompanyInfoRepository.getCurrentCompanyInfo();
      final settings = await PrinterSettingsRepository.getOrCreate();

      if (settings.selectedPrinterName == null ||
          settings.selectedPrinterName!.isEmpty) {
        return PrintTicketResult(
          success: false,
          message: 'No hay impresora configurada para abrir caja',
          ticketNumber: 'DRAWER',
        );
      }

      final layout = TicketLayoutConfig.fromPrinterSettings(settings);
      final builder = TicketBuilder(layout: layout, company: company);
      final pdf = builder.buildPdfFromLines(const <String>[' ', ' '], includeLogo: false);

      final result = await ThermalPrinterService.printDocument(
        document: pdf,
        settings: settings,
        overrideCopies: 1,
      );

      return PrintTicketResult(
        success: result.success,
        message: result.success
            ? 'Pulso de apertura enviado a caja registradora'
            : result.message,
        ticketNumber: 'DRAWER',
      );
    } catch (e) {
      return PrintTicketResult(
        success: false,
        message: 'Error al abrir caja: $e',
        ticketNumber: 'DRAWER',
      );
    }
  }

  /// Imprime una regla de ancho para verificar caracteres reales por línea.
  /// Recomendado para impresoras 80mm (576 dots): debe caber perfecto en 48.
  static Future<PrintTicketResult> printWidthRulerTest() async {
    try {
      final company = await CompanyInfoRepository.getCurrentCompanyInfo();
      final settings = await PrinterSettingsRepository.getOrCreate();
      final layout = TicketLayoutConfig.fromPrinterSettings(settings);

      final builder = TicketBuilder(layout: layout, company: company);
      final w = layout.maxCharsPerLine;

      String center(String text) {
        final t = text.trim();
        if (t.length >= w) return t.substring(0, w);
        final left = ((w - t.length) / 2).floor();
        final right = w - t.length - left;
        return ' ' * left + t + ' ' * right;
      }

      final ruler = builder.buildDebugRuler();
      final lr = (w >= 2) ? ('L${' ' * (w - 2)}R') : 'L';
      final line = List.filled(w, '-').join();

      final lines = <String>[
        center('PRUEBA DE ANCHO ($w CHARS)'),
        line,
        ruler,
        lr,
        line,
        center('SI SE CORTA: CAMBIE A 42'),
        '',
        '',
        '',
      ];

      final pdf = builder.buildPdfFromLines(lines, includeLogo: false);

      final result = await ThermalPrinterService.printDocument(
        document: pdf,
        settings: settings,
        overrideCopies: 1,
      );

      return PrintTicketResult(
        success: result.success,
        message: result.message,
        ticketNumber: 'RULER',
      );
    } catch (e) {
      return PrintTicketResult(
        success: false,
        message: 'Error: $e',
        ticketNumber: 'RULER',
      );
    }
  }

  // ============================================================
  // VISTA PREVIA (TEXTO PLANO)
  // ============================================================

  /// Genera vista previa en texto plano
  static Future<String> generatePreviewText({TicketData? data}) async {
    final company = await CompanyInfoRepository.getCurrentCompanyInfo();
    final settings = await PrinterSettingsRepository.getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);

    final builder = TicketBuilder(layout: layout, company: company);
    return builder.buildPlainText(data ?? TicketData.demo());
  }

  /// Obtiene configuración actual para la vista previa
  static Future<TicketPreviewConfig> getPreviewConfig() async {
    final company = await CompanyInfoRepository.getCurrentCompanyInfo();
    final settings = await PrinterSettingsRepository.getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);

    return TicketPreviewConfig(
      company: company,
      layout: layout,
      printerSettings: settings,
    );
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  /// Obtiene lista de impresoras disponibles
  static Future<List<Printer>> getAvailablePrinters() async {
    return await ThermalPrinterService.getAvailablePrinters();
  }

  /// Verifica el estado de la impresora
  static Future<PrinterStatus> checkPrinterStatus() async {
    return await ThermalPrinterService.checkPrinterStatus();
  }
}

/// Resultado de impresión de ticket
class PrintTicketResult {
  final bool success;
  final String message;
  final String ticketNumber;
  final bool skipped;

  PrintTicketResult({
    required this.success,
    required this.message,
    required this.ticketNumber,
    this.skipped = false,
  });
}

/// Configuración para vista previa
class TicketPreviewConfig {
  final CompanyInfo company;
  final TicketLayoutConfig layout;
  final PrinterSettingsModel printerSettings;

  TicketPreviewConfig({
    required this.company,
    required this.layout,
    required this.printerSettings,
  });
}
