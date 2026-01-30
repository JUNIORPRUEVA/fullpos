import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../features/settings/data/printer_settings_model.dart';
import '../../features/settings/data/printer_settings_repository.dart';

/// Servicio centralizado para impresión térmica USB de 80mm/58mm
/// Maneja la detección de impresoras y la impresión directa
class ThermalPrinterService {
  ThermalPrinterService._();

  static Printer? _cachedPrinter;
  static String? _cachedPrinterName;

  /// Obtiene todas las impresoras disponibles en el sistema
  static Future<List<Printer>> getAvailablePrinters() async {
    try {
      final printers = await Printing.listPrinters();
      debugPrint('🖨️ Impresoras encontradas: ${printers.length}');
      for (final p in printers) {
        debugPrint('  - ${p.name} (default: ${p.isDefault})');
      }
      return printers;
    } catch (e) {
      debugPrint('❌ Error al listar impresoras: $e');
      return [];
    }
  }

  /// Busca una impresora por nombre
  static Future<Printer?> findPrinter(String? printerName) async {
    if (printerName == null || printerName.isEmpty) return null;

    // Usar caché si el nombre coincide
    if (_cachedPrinter != null && _cachedPrinterName == printerName) {
      return _cachedPrinter;
    }

    final printers = await getAvailablePrinters();
    
    try {
      final printer = printers.firstWhere(
        (p) => p.name == printerName,
      );
      _cachedPrinter = printer;
      _cachedPrinterName = printerName;
      return printer;
    } catch (e) {
      debugPrint('⚠️ Impresora no encontrada: $printerName');
      return null;
    }
  }

  /// Verifica si hay una impresora configurada y disponible
  static Future<PrinterStatus> checkPrinterStatus() async {
    try {
      final settings = await PrinterSettingsRepository.getOrCreate();
      
      if (settings.selectedPrinterName == null || 
          settings.selectedPrinterName!.isEmpty) {
        return PrinterStatus(
          isConfigured: false,
          isAvailable: false,
          printerName: null,
          message: 'No hay impresora configurada',
        );
      }

      final printer = await findPrinter(settings.selectedPrinterName);
      
      if (printer == null) {
        return PrinterStatus(
          isConfigured: true,
          isAvailable: false,
          printerName: settings.selectedPrinterName,
          message: 'Impresora no encontrada: ${settings.selectedPrinterName}',
        );
      }

      return PrinterStatus(
        isConfigured: true,
        isAvailable: true,
        printerName: printer.name,
        message: 'Impresora lista: ${printer.name}',
        printer: printer,
      );
    } catch (e) {
      return PrinterStatus(
        isConfigured: false,
        isAvailable: false,
        printerName: null,
        message: 'Error al verificar impresora: $e',
      );
    }
  }

  /// Imprime un documento PDF directamente a la impresora térmica
  static Future<PrintResult> printDocument({
    required pw.Document document,
    PrinterSettingsModel? settings,
    int? overrideCopies,
  }) async {
    try {
      final printerSettings = settings ?? await PrinterSettingsRepository.getOrCreate();
      
      if (printerSettings.selectedPrinterName == null || 
          printerSettings.selectedPrinterName!.isEmpty) {
        return PrintResult(
          success: false,
          message: 'No hay impresora configurada',
        );
      }

      final copies = overrideCopies ?? printerSettings.copies;
      if (copies <= 0) {
        return PrintResult(
          success: true,
          message: 'Sin copias configuradas (0)',
        );
      }

      final printer = await findPrinter(printerSettings.selectedPrinterName);
      if (printer == null) {
        return PrintResult(
          success: false,
          message: 'Impresora no encontrada: ${printerSettings.selectedPrinterName}',
        );
      }

      debugPrint('🖨️ Imprimiendo $copies copia(s) a: ${printer.name}');

      final pdfBytes = await document.save();
      
      for (int i = 0; i < copies; i++) {
        final result = await Printing.directPrintPdf(
          printer: printer,
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'Ticket_${DateTime.now().millisecondsSinceEpoch}',
          usePrinterSettings: true,
        );
        
        if (!result) {
          return PrintResult(
            success: false,
            message: 'Error en copia ${i + 1} de $copies',
          );
        }
        
        // Sin pausas: la impresora/spooler maneja el pacing.
      }

      return PrintResult(
        success: true,
        message: '$copies copia(s) impresa(s) correctamente',
      );
    } catch (e) {
      debugPrint('❌ Error al imprimir: $e');
      return PrintResult(
        success: false,
        message: 'Error de impresión: $e',
      );
    }
  }

  /// Genera el formato de página para impresora térmica
  static PdfPageFormat getPageFormat(PrinterSettingsModel settings) {
    // Ancho real imprimible aproximado:
    // - 80mm típicamente imprime ~72mm (576 dots @ 203dpi)
    // - 58mm típicamente imprime ~48mm (384 dots @ 203dpi)
    final int printableMm = settings.paperWidthMm == 80 ? 72 : 48;
    final double widthPts = printableMm * PdfPageFormat.mm;
    
    // Alto del rollo: usar un valor grande FINITO.
    // En algunos drivers/spoolers (Windows) `double.infinity` puede imprimir en blanco.
    final double heightPts = 2000 * PdfPageFormat.mm;
    
    return PdfPageFormat(
      widthPts,
      heightPts,
      marginLeft: (settings.leftMargin.clamp(0, 4)) * PdfPageFormat.mm,
      marginRight: (settings.rightMargin.clamp(0, 4)) * PdfPageFormat.mm,
      marginTop: 2 * PdfPageFormat.mm,
      marginBottom: 2 * PdfPageFormat.mm,
    );
  }

  /// Limpiar caché de impresora
  static void clearCache() {
    _cachedPrinter = null;
    _cachedPrinterName = null;
  }
}

/// Estado de la impresora
class PrinterStatus {
  final bool isConfigured;
  final bool isAvailable;
  final String? printerName;
  final String message;
  final Printer? printer;

  PrinterStatus({
    required this.isConfigured,
    required this.isAvailable,
    required this.printerName,
    required this.message,
    this.printer,
  });

  bool get isReady => isConfigured && isAvailable;
}

/// Resultado de impresión
class PrintResult {
  final bool success;
  final String message;

  PrintResult({
    required this.success,
    required this.message,
  });
}
