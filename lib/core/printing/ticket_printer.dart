import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/app_configuration_service.dart';
import '../../features/settings/data/printer_settings_model.dart';
import '../../features/settings/data/printer_settings_repository.dart';
import '../../features/sales/data/sales_model.dart';
import 'thermal_printer_service.dart';
import 'ticket_template.dart';

/// @deprecated Use [UnifiedTicketPrinter] instead.
/// Este servicio ha sido reemplazado por UnifiedTicketPrinter que usa
/// una arquitectura centralizada con CompanyInfo como fuente única de datos.
///
/// La impresora de tickets de venta para impresoras térmicas USB (80mm/58mm)
@Deprecated('Use UnifiedTicketPrinter instead for centralized company data')
class TicketPrinter {
  TicketPrinter._();

  static String _resolveBusinessName(String headerBusinessName) {
    final header = headerBusinessName.trim();
    final headerUpper = header.toUpperCase();
    final business = appConfigService.getBusinessName().trim();
    final shouldFallback =
        header.isEmpty ||
        headerUpper == 'FULLTECH, SRL' ||
        headerUpper == 'FULLPOS';
    if (shouldFallback && business.isNotEmpty) {
      return business;
    }
    return header.isNotEmpty ? header : business;
  }

  static String _resolvePoweredByLine() {
    return 'Powered by FULLTECH, SRL';
  }

  /// Obtiene lista de impresoras disponibles
  static Future<List<Printer>> getAvailablePrinters() async {
    return await ThermalPrinterService.getAvailablePrinters();
  }

  /// Imprime un ticket de venta directamente a la impresora
  static Future<bool> printTicket({
    required PrinterSettingsModel settings,
    required SaleModel sale,
    required List<SaleItemModel> items,
    String? cashierName,
  }) async {
    try {
      final pdf = _generateTicketPdf(
        settings: settings,
        sale: sale,
        items: items,
        cashierName: cashierName,
      );

      final result = await ThermalPrinterService.printDocument(
        document: pdf,
        settings: settings,
      );

      if (result.success) {
        debugPrint('✅ Ticket impreso: ${sale.localCode}');
      } else {
        debugPrint('❌ Error imprimiendo ticket: ${result.message}');
      }

      return result.success;
    } catch (e) {
      debugPrint('❌ Error en printTicket: $e');
      return false;
    }
  }

  /// Imprime un ticket de prueba
  static Future<bool> printTestTicket(PrinterSettingsModel settings) async {
    try {
      final testContent = TicketTemplate.generateDemoTicket(settings);
      final pdf = _generateTextPdf(testContent, settings);

      final result = await ThermalPrinterService.printDocument(
        document: pdf,
        settings: settings,
        overrideCopies: 1,
      );

      return result.success;
    } catch (e) {
      debugPrint('❌ Error en printTestTicket: $e');
      return false;
    }
  }

  /// Imprime una venta automáticamente si está habilitado
  static Future<bool> printSale({
    required SaleModel sale,
    required List<SaleItemModel> items,
    String? cashierName,
  }) async {
    try {
      final settings = await PrinterSettingsRepository.getOrCreate();

      if (settings.autoPrintOnPayment != 1) {
        debugPrint('ℹ️ Auto-print desactivado');
        return true;
      }

      return await printTicket(
        settings: settings,
        sale: sale,
        items: items,
        cashierName: cashierName,
      );
    } catch (e) {
      debugPrint('❌ Error en printSale: $e');
      return false;
    }
  }

  /// Reimprime una venta (ignora autoPrintOnPayment)
  static Future<bool> reprintSale({
    required SaleModel sale,
    required List<SaleItemModel> items,
    String? cashierName,
    int? overrideCopies,
  }) async {
    try {
      var settings = await PrinterSettingsRepository.getOrCreate();

      if (overrideCopies != null) {
        settings = settings.copyWith(copies: overrideCopies);
      }

      return await printTicket(
        settings: settings,
        sale: sale,
        items: items,
        cashierName: cashierName,
      );
    } catch (e) {
      debugPrint('❌ Error en reprintSale: $e');
      return false;
    }
  }

  /// Genera PDF del ticket optimizado para impresora térmica
  static pw.Document _generateTicketPdf({
    required PrinterSettingsModel settings,
    required SaleModel sale,
    required List<SaleItemModel> items,
    String? cashierName,
  }) {
    final doc = pw.Document();

    // Calcular tamaño de página para rollo térmico
    final double pageWidth = settings.paperWidthMm * PdfPageFormat.mm;

    // === USAR CONFIGURACIÓN DE FUENTES ===
    final pw.Font baseFont;
    final pw.Font boldFont;

    // Seleccionar fuente según configuración
    switch (settings.fontFamily) {
      case 'arial':
        baseFont = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
        break;
      case 'arialBlack':
        baseFont = pw.Font.helveticaBold();
        boldFont = pw.Font.helveticaBold();
        break;
      case 'roboto':
      case 'sansSerif':
        baseFont = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
        break;
      default: // 'courier'
        baseFont = pw.Font.courier();
        boldFont = pw.Font.courierBold();
    }

    // === USAR TAMAÑO DE FUENTE CONFIGURADO ===
    final double configuredFontSize = settings.fontSizeValue;
    final double titleSize = configuredFontSize + 2.0;
    final double normalSize = configuredFontSize;
    final double smallSize = configuredFontSize - 1.0;

    // Construir contenido del ticket
    final content = <pw.Widget>[];
    final separator = pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Text(
        '-' * settings.charsPerLine,
        style: pw.TextStyle(font: baseFont, fontSize: smallSize),
      ),
    );

    // === HEADER ===
    final businessName = _resolveBusinessName(settings.headerBusinessName);

    // Solo mostrar datos del negocio si está habilitado
    if (settings.showBusinessData == 1) {
      content.add(
        pw.Center(
          child: pw.Text(
            businessName.toUpperCase(),
            style: pw.TextStyle(font: boldFont, fontSize: titleSize),
            textAlign: pw.TextAlign.center,
          ),
        ),
      );

      if ((settings.headerRnc ?? '').isNotEmpty) {
        content.add(
          pw.Center(
            child: pw.Text(
              'RNC: ${settings.headerRnc}',
              style: pw.TextStyle(font: baseFont, fontSize: normalSize),
            ),
          ),
        );
      }

      if ((settings.headerAddress ?? '').isNotEmpty) {
        content.add(
          pw.Center(
            child: pw.Text(
              settings.headerAddress!,
              style: pw.TextStyle(font: baseFont, fontSize: smallSize),
              textAlign: pw.TextAlign.center,
            ),
          ),
        );
      }

      if ((settings.headerPhone ?? '').isNotEmpty) {
        content.add(
          pw.Center(
            child: pw.Text(
              'Tel: ${settings.headerPhone}',
              style: pw.TextStyle(font: baseFont, fontSize: normalSize),
            ),
          ),
        );
      }

      if ((settings.headerExtra ?? '').isNotEmpty) {
        content.add(
          pw.Center(
            child: pw.Text(
              settings.headerExtra!,
              style: pw.TextStyle(font: baseFont, fontSize: smallSize),
              textAlign: pw.TextAlign.center,
            ),
          ),
        );
      }

      content.add(separator);
    }

    // === FECHA/HORA Y CÓDIGO ===
    if (settings.showDatetime == 1) {
      final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
      content.add(
        pw.Center(
          child: pw.Text(
            _formatDate(date),
            style: pw.TextStyle(font: baseFont, fontSize: normalSize),
          ),
        ),
      );
    }

    if (settings.showCode == 1) {
      content.add(
        pw.Center(
          child: pw.Text(
            'TICKET #${sale.localCode}',
            style: pw.TextStyle(font: boldFont, fontSize: normalSize),
          ),
        ),
      );
    }

    if ((settings.showNcf == 1 || sale.fiscalEnabled == 1) &&
        (sale.ncfFull ?? '').isNotEmpty) {
      content.add(
        pw.Center(
          child: pw.Text(
            'NCF: ${sale.ncfFull}',
            style: pw.TextStyle(font: baseFont, fontSize: normalSize),
          ),
        ),
      );
    }

    content.add(separator);

    // === CLIENTE ===
    if (settings.showClient == 1 &&
        (sale.customerNameSnapshot ?? '').isNotEmpty) {
      content.add(
        pw.Text(
          'Cliente: ${sale.customerNameSnapshot}',
          style: pw.TextStyle(font: baseFont, fontSize: normalSize),
        ),
      );
      if ((sale.customerPhoneSnapshot ?? '').isNotEmpty) {
        content.add(
          pw.Text(
            'Tel: ${sale.customerPhoneSnapshot}',
            style: pw.TextStyle(font: baseFont, fontSize: smallSize),
          ),
        );
      }
      content.add(separator);
    }

    // === CAJERO ===
    if (settings.showCashier == 1 && (cashierName ?? '').isNotEmpty) {
      content.add(
        pw.Text(
          'Cajero: $cashierName',
          style: pw.TextStyle(font: baseFont, fontSize: normalSize),
        ),
      );
      content.add(separator);
    }

    // === ITEMS ===
    content.add(
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'DESCRIPCIÓN',
            style: pw.TextStyle(font: boldFont, fontSize: smallSize),
          ),
          pw.Text(
            'TOTAL',
            style: pw.TextStyle(font: boldFont, fontSize: smallSize),
          ),
        ],
      ),
    );
    content.add(pw.SizedBox(height: 2));

    for (final item in items) {
      content.add(
        pw.Text(
          _truncate(item.productNameSnapshot, settings.charsPerLine - 10),
          style: pw.TextStyle(font: baseFont, fontSize: normalSize),
        ),
      );
      content.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '  ${_formatQty(item.qty)} x ${_formatCurrency(item.unitPrice)}',
              style: pw.TextStyle(font: baseFont, fontSize: smallSize),
            ),
            pw.Text(
              _formatCurrency(item.totalLine),
              style: pw.TextStyle(font: baseFont, fontSize: normalSize),
            ),
          ],
        ),
      );
      content.add(pw.SizedBox(height: 3));
    }

    content.add(separator);

    // === TOTALES ===
    // Solo mostrar desglose si está habilitado
    if (settings.showSubtotalItbisTotal == 1) {
      content.add(
        _buildTotalRow(
          'Subtotal:',
          _formatCurrency(sale.subtotal),
          baseFont,
          normalSize,
        ),
      );

      if ((sale.discountTotal) > 0) {
        content.add(
          _buildTotalRow(
            'Descuento:',
            '-${_formatCurrency(sale.discountTotal)}',
            baseFont,
            normalSize,
          ),
        );
      }

      if (settings.showItbis == 1 && sale.itbisAmount > 0) {
        final itbisPercent = (sale.itbisRate * 100).toStringAsFixed(0);
        content.add(
          _buildTotalRow(
            'ITBIS ($itbisPercent%):',
            _formatCurrency(sale.itbisAmount),
            baseFont,
            normalSize,
          ),
        );
      }

      content.add(pw.SizedBox(height: 4));
    }

    // TOTAL siempre se muestra
    content.add(
      _buildTotalRow(
        'TOTAL:',
        _formatCurrency(sale.total),
        boldFont,
        titleSize,
      ),
    );
    content.add(pw.SizedBox(height: 4));

    content.add(separator);

    // === PAGO ===
    if (settings.showPaymentMethod == 1 &&
        (sale.paymentMethod ?? '').isNotEmpty) {
      content.add(
        pw.Center(
          child: pw.Text(
            'Pago: ${_translatePaymentMethod(sale.paymentMethod!)}',
            style: pw.TextStyle(font: baseFont, fontSize: normalSize),
          ),
        ),
      );
    }

    if (sale.paidAmount > 0) {
      content.add(
        _buildTotalRow(
          'Recibido:',
          _formatCurrency(sale.paidAmount),
          baseFont,
          normalSize,
        ),
      );
    }

    if (sale.changeAmount > 0) {
      content.add(
        _buildTotalRow(
          'Cambio:',
          _formatCurrency(sale.changeAmount),
          baseFont,
          normalSize,
        ),
      );
    }

    content.add(separator);

    // === FOOTER ===
    content.add(pw.SizedBox(height: 4));
    content.add(
      pw.Center(
        child: pw.Text(
          settings.footerMessage,
          style: pw.TextStyle(font: baseFont, fontSize: normalSize),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
    content.add(pw.SizedBox(height: 2));
    content.add(
      pw.Center(
        child: pw.Text(
          _resolvePoweredByLine(),
          style: pw.TextStyle(font: baseFont, fontSize: smallSize),
        ),
      ),
    );

    // Espacio para corte
    if (settings.autoCut == 1) {
      content.add(pw.SizedBox(height: 30));
    }

    // Crear página con tamaño dinámico
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidth,
          double.infinity,
          marginLeft: settings.leftMargin * PdfPageFormat.mm + 2,
          marginRight: settings.rightMargin * PdfPageFormat.mm + 2,
          marginTop: settings.topMargin.toDouble(),
          marginBottom: settings.bottomMargin.toDouble(),
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: content,
        ),
      ),
    );

    return doc;
  }

  /// Genera PDF de texto simple
  static pw.Document _generateTextPdf(
    String content,
    PrinterSettingsModel settings,
  ) {
    final doc = pw.Document();

    final double pageWidth = settings.paperWidthMm * PdfPageFormat.mm;

    // Usar configuración de fuente
    final pw.Font font;
    switch (settings.fontFamily) {
      case 'arial':
      case 'arialBlack':
      case 'roboto':
      case 'sansSerif':
        font = pw.Font.helvetica();
        break;
      default:
        font = pw.Font.courier();
    }

    final fontSize = settings.fontSizeValue;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidth,
          double.infinity,
          marginLeft: settings.leftMargin * PdfPageFormat.mm + 2,
          marginRight: settings.rightMargin * PdfPageFormat.mm + 2,
          marginTop: settings.topMargin.toDouble(),
          marginBottom: settings.bottomMargin.toDouble(),
        ),
        build: (context) => pw.Text(
          content,
          style: pw.TextStyle(font: font, fontSize: fontSize),
        ),
      ),
    );

    return doc;
  }

  // Helpers
  static pw.Widget _buildTotalRow(
    String label,
    String value,
    pw.Font font,
    double fontSize,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(font: font, fontSize: fontSize),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(font: font, fontSize: fontSize),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year;
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min:$s';
  }

  static String _formatCurrency(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }

  static String _formatQty(double qty) {
    if (qty == qty.truncateToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(2);
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
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
}
