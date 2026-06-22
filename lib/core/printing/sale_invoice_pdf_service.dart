import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../features/sales/data/sales_model.dart';
import '../../features/sales/data/sales_repository.dart';
import '../../features/settings/data/business_settings_model.dart';
import '../../features/settings/data/business_settings_repository.dart';
import '../../features/settings/data/printer_settings_repository.dart';
import '../../core/session/session_manager.dart';
import 'invoice_letter_pdf.dart';

/// Servicio para generar, visualizar, guardar y compartir facturas en PDF carta.
///
/// Reutiliza [InvoiceLetterPdf.generate] para la generación del PDF.
/// No modifica la lógica de ventas ni de impresión térmica.
class SaleInvoicePdfService {
  SaleInvoicePdfService._();

  /// Genera los bytes del PDF carta para una venta.
  ///
  /// [saleId] ID de la venta.
  /// [brandColorArgb] Color de marca en ARGB (opcional, por defecto 0xFF1A56DB).
  static Future<Uint8List> generateLetterPdf({
    required int saleId,
    int brandColorArgb = 0xFF1A56DB,
  }) async {
    final sale = await SalesRepository.getSaleById(saleId);
    if (sale == null) {
      throw Exception('No se pudo cargar la venta #$saleId.');
    }

    final items = await SalesRepository.getItemsBySaleId(saleId);
    final business = await BusinessSettingsRepository().loadSettings();
    final printerSettings = await PrinterSettingsRepository.getOrCreate();
    final cashierName = await SessionManager.displayName() ?? 'Cajero';

    return InvoiceLetterPdf.generate(
      sale: sale,
      items: items,
      business: business,
      brandColorArgb: brandColorArgb,
      cashierName: cashierName,
      warrantyPolicy: printerSettings.warrantyPolicy,
      footerMessage: printerSettings.footerMessage,
    );
  }

  /// Genera los bytes del PDF carta a partir de objetos ya cargados.
  static Future<Uint8List> generateLetterPdfFromData({
    required SaleModel sale,
    required List<SaleItemModel> items,
    required BusinessSettings business,
    int brandColorArgb = 0xFF1A56DB,
    String? cashierName,
    String? warrantyPolicy,
    String? footerMessage,
  }) async {
    final resolvedCashierName = cashierName ?? await SessionManager.displayName() ?? 'Cajero';
    String? resolvedWarrantyPolicy = warrantyPolicy;
    String? resolvedFooterMessage = footerMessage;

    if (resolvedWarrantyPolicy == null || resolvedFooterMessage == null) {
      try {
        final printerSettings = await PrinterSettingsRepository.getOrCreate();
        resolvedWarrantyPolicy ??= printerSettings.warrantyPolicy;
        resolvedFooterMessage ??= printerSettings.footerMessage;
      } catch (_) {
        // fallback
      }
    }

    return InvoiceLetterPdf.generate(
      sale: sale,
      items: items,
      business: business,
      brandColorArgb: brandColorArgb,
      cashierName: resolvedCashierName,
      warrantyPolicy: resolvedWarrantyPolicy,
      footerMessage: resolvedFooterMessage,
    );
  }

  /// Guarda el PDF en el directorio de Descargas (o Documents como fallback).
  ///
  /// Retorna la ruta completa del archivo guardado.
  static Future<String> savePdfToDownloads({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final downloadsDir = await _getBestDownloadDirectory();
    final file = File('${downloadsDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Comparte el PDF usando [Share.shareXFiles] o [Printing.sharePdf].
  static Future<void> sharePdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      // Intentar usar share_plus primero
      final dir = await _getBestDownloadDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Factura PDF',
      );
    } catch (_) {
      // Fallback a Printing.sharePdf
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  /// Muestra una vista previa del PDF en un diálogo/pantalla.
  ///
  /// [context] Contexto de Flutter.
  /// [bytes] Datos del PDF.
  /// [title] Título de la vista previa.
  /// [fileName] Nombre del archivo para guardar/compartir.
  static Future<void> showPdfPreview({
    required BuildContext context,
    required Uint8List bytes,
    required String title,
    required String fileName,
  }) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => _SalePdfPreviewPage(
          pdfBytes: bytes,
          title: title,
          fileName: fileName,
        ),
      ),
    );
  }

  /// Obtiene el mejor directorio para guardar (Downloads > Documents).
  static Future<Directory> _getBestDownloadDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationDocumentsDirectory();
  }

  /// Genera un nombre de archivo seguro para la factura.
  static String buildFileName({
    required String saleCode,
    required String clientName,
  }) {
    final safeClient = _sanitizeFilenamePart(clientName);
    final safeCode = _sanitizeFilenamePart(saleCode);
    final dateStr = DateTime.now().millisecondsSinceEpoch.toString();
    return 'Factura_${safeCode}_$dateStr.pdf';
  }

  static String _sanitizeFilenamePart(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'CLIENTE';
    final noBadChars = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final collapsedSpaces = noBadChars.replaceAll(RegExp(r'\s+'), ' ');
    return collapsedSpaces;
  }
}

// ─────────────────────────────────────────────────────────────
// PDF PREVIEW PAGE
// ─────────────────────────────────────────────────────────────

class _SalePdfPreviewPage extends StatefulWidget {
  final Uint8List pdfBytes;
  final String title;
  final String fileName;

  const _SalePdfPreviewPage({
    required this.pdfBytes,
    required this.title,
    required this.fileName,
  });

  @override
  State<_SalePdfPreviewPage> createState() => _SalePdfPreviewPageState();
}

class _SalePdfPreviewPageState extends State<_SalePdfPreviewPage> {
  late Uint8List _pdfBytes;
  double _previewZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _pdfBytes = widget.pdfBytes;
  }

  void _zoomIn() {
    setState(() => _previewZoom = (_previewZoom + 0.10).clamp(0.5, 2.0));
  }

  void _zoomOut() {
    setState(() => _previewZoom = (_previewZoom - 0.10).clamp(0.5, 2.0));
  }

  void _resetZoom() {
    setState(() => _previewZoom = 1.0);
  }

  Future<void> _downloadPdf() async {
    try {
      final path = await SaleInvoicePdfService.savePdfToDownloads(
        bytes: _pdfBytes,
        fileName: widget.fileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF guardado: $path'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el PDF.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sharePdf() async {
    try {
      await SaleInvoicePdfService.sharePdf(
        bytes: _pdfBytes,
        fileName: widget.fileName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo compartir el PDF.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          // Zoom out
          IconButton(
            icon: const Icon(Icons.remove_rounded, size: 20),
            tooltip: 'Alejar',
            onPressed: _zoomOut,
            color: const Color(0xFF475569),
          ),
          Text(
            '${(_previewZoom * 100).round()}%',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          // Zoom in
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 20),
            tooltip: 'Acercar',
            onPressed: _zoomIn,
            color: const Color(0xFF475569),
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
            tooltip: 'Restablecer zoom',
            onPressed: _resetZoom,
            color: const Color(0xFF475569),
          ),
          const SizedBox(width: 4),
          // Download
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Descargar PDF',
            onPressed: _downloadPdf,
            color: scheme.primary,
          ),
          // Share
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Compartir PDF',
            onPressed: _sharePdf,
            color: scheme.primary,
          ),
          // Print
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Imprimir PDF',
            onPressed: () async {
              await Printing.layoutPdf(onLayout: (_) => _pdfBytes);
            },
            color: const Color(0xFF475569),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: PdfPreview(
          build: (_) async => _pdfBytes,
          canChangeOrientation: false,
          canChangePageFormat: false,
          allowPrinting: false,
          allowSharing: false,
          canDebug: false,
          useActions: false,
          maxPageWidth: (MediaQuery.of(context).size.width * 0.55)
              .clamp(500.0, 900.0) * _previewZoom,
          padding: EdgeInsets.zero,
          scrollViewDecoration: const BoxDecoration(
            color: Color(0xFFF2F6F9),
          ),
          pdfPreviewPageDecoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
