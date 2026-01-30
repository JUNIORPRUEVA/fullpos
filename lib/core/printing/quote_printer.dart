import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../features/sales/data/business_info_model.dart';
import '../../features/sales/data/quote_model.dart';
import '../../features/settings/data/business_settings_model.dart';
import '../../features/settings/data/printer_settings_model.dart';
import '../layout/app_shell.dart';
import '../services/empresa_service.dart';

/// Servicio para imprimir y generar PDF de cotizaciones.
class QuotePrinter {
  QuotePrinter._();

  static String _sanitizePdfText(String input) {
    var s = input.replaceAll('\u00A0', ' ');
    s = s
        .replaceAll('\u2022', '-') // bullet
        .replaceAll('\u2013', '-') // en-dash
        .replaceAll('\u2014', '-') // em-dash
        .replaceAll('\u2026', '...') // ellipsis
        .replaceAll('\u00B7', '-') // middle dot
        .replaceAll('\u00AD', ''); // soft hyphen
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Map<String, String> _normalizeBusinessData(dynamic business) {
    final normalized = <String, String>{
      'name': 'FULLPOS',
      'slogan': '',
      'address': '',
      'city': '',
      'phone': '',
      'phone2': '',
      'rnc': '',
      'email': '',
      'website': '',
      'instagram': '',
      'facebook': '',
    };

    if (business is BusinessSettings) {
      normalized['name'] = business.businessName;
      normalized['slogan'] = business.slogan ?? '';
      normalized['address'] = business.address ?? '';
      normalized['city'] = business.city ?? '';
      normalized['phone'] = business.phone ?? '';
      normalized['phone2'] = business.phone2 ?? '';
      normalized['rnc'] = business.rnc ?? '';
      normalized['email'] = business.email ?? '';
      normalized['website'] = business.website ?? '';
      normalized['instagram'] = business.instagramUrl ?? '';
      normalized['facebook'] = business.facebookUrl ?? '';
    } else if (business is BusinessInfoModel) {
      normalized['name'] = business.name;
      normalized['slogan'] = business.slogan ?? '';
      normalized['address'] = business.address ?? '';
      normalized['phone'] = business.phone ?? '';
      normalized['rnc'] = business.rnc ?? '';
    }

    return normalized;
  }

  static Future<Map<String, String>> _getEmpresaDataFromConfig() async {
    try {
      final config = await EmpresaService.getEmpresaConfig();

      return {
        'name': config.nombreEmpresa,
        'slogan': config.slogan ?? '',
        'address': config.direccion ?? '',
        'city': config.ciudad ?? '',
        'phone': config.getTelefono() ?? '',
        'phone2': config.telefono2 ?? '',
        'rnc': config.rnc ?? '',
        'email': config.email ?? '',
        'website': config.website ?? '',
        'instagram': config.instagramUrl ?? '',
        'facebook': config.facebookUrl ?? '',
      };
    } catch (e) {
      debugPrint('Error en _getEmpresaDataFromConfig: $e');
      return {
        'name': 'FULLPOS',
        'slogan': '',
        'address': '',
        'city': '',
        'phone': '',
        'phone2': '',
        'rnc': '',
        'email': '',
        'website': '',
        'instagram': '',
        'facebook': '',
      };
    }
  }

  static Future<Map<String, String>> _resolveBusinessData(
    dynamic business,
  ) async {
    final empresaData = await _getEmpresaDataFromConfig();
    final name = (empresaData['name'] ?? '').trim();
    final hasDetails = empresaData.entries.any(
      (entry) => entry.key != 'name' && entry.value.trim().isNotEmpty,
    );

    if (business != null &&
        (!hasDetails &&
            (name.isEmpty || name == 'Mi Negocio' || name == 'FULLPOS'))) {
      return _normalizeBusinessData(business);
    }

    if (business != null && name == 'Mi Negocio') {
      return _normalizeBusinessData(business);
    }

    return empresaData;
  }

  static Future<Uint8List> generatePdf({
    required QuoteModel quote,
    required List<QuoteItemModel> items,
    required String clientName,
    String? clientPhone,
    String? clientRnc,
    dynamic business,
    int validDays = 15,
  }) async {
    final businessData = await _resolveBusinessData(business);
    final payload = <String, dynamic>{
      'quote': quote.toMap(),
      'items': items.map((item) => item.toMap()).toList(),
      'clientName': clientName,
      'clientPhone': clientPhone,
      'clientRnc': clientRnc,
      'business': businessData,
      'validDays': validDays,
    };

    if (kIsWeb) {
      return _generatePdfInternal(payload);
    }

    try {
      return await compute(_generatePdfIsolate, payload);
    } catch (e) {
      debugPrint('Quote PDF isolate failed: $e');
      return _generatePdfInternal(payload);
    }
  }

  static Future<Uint8List> _generatePdfIsolate(
    Map<String, dynamic> payload,
  ) async {
    return _generatePdfInternal(payload);
  }

  static Future<Uint8List> _generatePdfInternal(
    Map<String, dynamic> payload,
  ) async {
    final quote = QuoteModel.fromMap(
      Map<String, dynamic>.from(payload['quote'] as Map),
    );
    final items = (payload['items'] as List)
        .map(
          (item) =>
              QuoteItemModel.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final businessData = Map<String, String>.from(payload['business'] as Map);
    final clientName = payload['clientName'] as String? ?? '';
    final clientPhone = payload['clientPhone'] as String?;
    final clientRnc = payload['clientRnc'] as String?;
    final validDays = payload['validDays'] as int? ?? 15;

    final fonts = await _loadPdfFonts();
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
    );

    final safeBusiness = businessData.map(
      (k, v) => MapEntry(k, _sanitizePdfText(v)),
    );
    final safeClientName = _sanitizePdfText(clientName);
    final safeClientPhone = clientPhone == null
        ? null
        : _sanitizePdfText(clientPhone);
    final safeClientRnc = clientRnc == null
        ? null
        : _sanitizePdfText(clientRnc);

    final createdDate = DateTime.fromMillisecondsSinceEpoch(quote.createdAtMs);
    final expirationDate = createdDate.add(Duration(days: validDays));
    final issueDate = DateFormat('dd/MM/yyyy HH:mm').format(createdDate);
    final validUntil = DateFormat('dd/MM/yyyy').format(expirationDate);
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        header: (context) =>
            _buildHeader(safeBusiness, quote, issueDate, validUntil),
        footer: (context) =>
            _buildFooter(context, safeBusiness, quote, currencyFormat),
        build: (context) => [
          _buildInfoBlocks(
            safeBusiness,
            safeClientName.isEmpty ? 'Cliente' : safeClientName,
            safeClientPhone,
            safeClientRnc,
          ),
          pw.SizedBox(height: 14),
          _buildProductsTable(items, currencyFormat),
          if (quote.notes != null && quote.notes!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _buildNotes(_sanitizePdfText(quote.notes!)),
          ],
          pw.SizedBox(height: 14),
          _buildTerms(validDays),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<_PdfFonts> _loadPdfFonts() async {
    try {
      if (Platform.isWindows) {
        final regular = File(r'C:\\Windows\\Fonts\\segoeui.ttf');
        final bold = File(r'C:\\Windows\\Fonts\\segoeuib.ttf');
        if (regular.existsSync() && bold.existsSync()) {
          return _PdfFonts(
            base: pw.Font.ttf(ByteData.view(regular.readAsBytesSync().buffer)),
            bold: pw.Font.ttf(ByteData.view(bold.readAsBytesSync().buffer)),
          );
        }

        final arial = File(r'C:\\Windows\\Fonts\\arial.ttf');
        final arialBold = File(r'C:\\Windows\\Fonts\\arialbd.ttf');
        if (arial.existsSync() && arialBold.existsSync()) {
          return _PdfFonts(
            base: pw.Font.ttf(ByteData.view(arial.readAsBytesSync().buffer)),
            bold: pw.Font.ttf(
              ByteData.view(arialBold.readAsBytesSync().buffer),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Font load failed: $e');
    }

    return _PdfFonts(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
  }

  static pw.Widget _buildHeader(
    Map<String, String> businessData,
    QuoteModel quote,
    String issueDate,
    String validUntil,
  ) {
    final displayId = quote.id != null
        ? quote.id!.toString().padLeft(5, '0')
        : '-----';
    final phones = _joinParts([
      businessData['phone'] ?? '',
      businessData['phone2'] ?? '',
    ], separator: ' / ');
    final address = _joinParts([
      businessData['address'] ?? '',
      businessData['city'] ?? '',
    ], separator: ', ');

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  businessData['name']!.isNotEmpty
                      ? businessData['name']!
                      : 'Empresa',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (businessData['slogan']!.isNotEmpty)
                  pw.Text(
                    businessData['slogan']!,
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                if (address.isNotEmpty)
                  pw.Text(address, style: const pw.TextStyle(fontSize: 9)),
                if (phones.isNotEmpty)
                  pw.Text(
                    'Tel: $phones',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (businessData['email']!.isNotEmpty)
                  pw.Text(
                    businessData['email']!,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (businessData['rnc']!.isNotEmpty)
                  pw.Text(
                    'RNC: ${businessData['rnc']!}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.teal,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'COTIZACION',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  '#COT-$displayId',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Fecha: $issueDate',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  'Valida hasta: $validUntil',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoBlocks(
    Map<String, String> businessData,
    String clientName,
    String? clientPhone,
    String? clientRnc,
  ) {
    final companyLines = <pw.Widget>[];
    final address = _joinParts([
      businessData['address'] ?? '',
      businessData['city'] ?? '',
    ], separator: ', ');
    final phones = _joinParts([
      businessData['phone'] ?? '',
      businessData['phone2'] ?? '',
    ], separator: ' / ');

    if (address.isNotEmpty) {
      companyLines.add(_infoLine('Direccion', address));
    }
    if (phones.isNotEmpty) {
      companyLines.add(_infoLine('Telefono', phones));
    }
    if (businessData['email']!.isNotEmpty) {
      companyLines.add(_infoLine('Correo', businessData['email']!));
    }
    if (businessData['website']!.isNotEmpty) {
      companyLines.add(_infoLine('Web', businessData['website']!));
    }
    if (businessData['rnc']!.isNotEmpty) {
      companyLines.add(_infoLine('RNC', businessData['rnc']!));
    }

    final clientLines = <pw.Widget>[_infoLine('Nombre', clientName)];
    if (clientPhone != null && clientPhone.isNotEmpty) {
      clientLines.add(_infoLine('Telefono', clientPhone));
    }
    if (clientRnc != null && clientRnc.isNotEmpty) {
      clientLines.add(_infoLine('RNC', clientRnc));
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _buildInfoCard('Empresa', companyLines)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _buildInfoCard('Cliente', clientLines)),
      ],
    );
  }

  static pw.Widget _buildInfoCard(String title, List<pw.Widget> lines) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 6),
          ...lines,
        ],
      ),
    );
  }

  static pw.Widget _infoLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.RichText(
        text: pw.TextSpan(
          text: '$label: ',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
          children: [
            pw.TextSpan(
              text: value,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.normal,
                color: PdfColors.grey800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildProductsTable(
    List<QuoteItemModel> items,
    NumberFormat currencyFormat,
  ) {
    final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );
    final bodyStyle = const pw.TextStyle(fontSize: 9);

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.teal),
        children: [
          _tableCell('DESCRIPCION', headerStyle),
          _tableCell('CANT', headerStyle, align: pw.TextAlign.center),
          _tableCell('PRECIO', headerStyle, align: pw.TextAlign.right),
          _tableCell('DESC', headerStyle, align: pw.TextAlign.right),
          _tableCell('TOTAL', headerStyle, align: pw.TextAlign.right),
        ],
      ),
    ];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final isAlt = i.isOdd;
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isAlt ? PdfColors.grey100 : PdfColors.white,
          ),
          children: [
            _tableCell(_sanitizePdfText(item.description), bodyStyle),
            _tableCell(
              _formatQty(item.qty),
              bodyStyle,
              align: pw.TextAlign.center,
            ),
            _tableCell(
              _formatMoney(currencyFormat, item.price),
              bodyStyle,
              align: pw.TextAlign.right,
            ),
            _tableCell(
              item.discountLine > 0
                  ? _formatMoney(currencyFormat, item.discountLine)
                  : '-',
              bodyStyle,
              align: pw.TextAlign.right,
            ),
            _tableCell(
              _formatMoney(currencyFormat, item.totalLine),
              pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              align: pw.TextAlign.right,
            ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.7),
      },
      children: rows,
    );
  }

  static pw.Widget _tableCell(
    String text,
    pw.TextStyle style, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }

  static pw.Widget _buildNotes(String notes) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Notas',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(notes, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  static pw.Widget _buildTerms(int validDays) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Terminos',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '- Validez: $validDays dias.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            '- Precios sujetos a cambios luego del vencimiento.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            '- ITBIS incluido segun normativa local.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(
    pw.Context context,
    Map<String, String> businessData,
    QuoteModel quote,
    NumberFormat currencyFormat,
  ) {
    final showTotals = context.pageNumber == context.pagesCount;
    final footerParts = <String>[];

    if (businessData['website']!.isNotEmpty) {
      footerParts.add(businessData['website']!);
    }
    if (businessData['email']!.isNotEmpty) {
      footerParts.add(businessData['email']!);
    }
    if (businessData['instagram']!.isNotEmpty) {
      footerParts.add('Instagram: ${businessData['instagram']!}');
    }
    if (businessData['facebook']!.isNotEmpty) {
      footerParts.add('Facebook: ${businessData['facebook']!}');
    }

    final footerText = footerParts.join(' | ');

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (showTotals) _buildTotalsFooter(quote, currencyFormat),
        pw.SizedBox(height: 8),
        pw.Container(height: 1, color: PdfColors.grey400),
        if (footerText.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            footerText,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ],
    );
  }

  static pw.Widget _buildTotalsFooter(
    QuoteModel quote,
    NumberFormat currencyFormat,
  ) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 260,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.teal50,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: PdfColors.teal200),
        ),
        child: pw.Column(
          children: [
            _totalsRow('Subtotal', quote.subtotal, currencyFormat),
            if (quote.discountTotal > 0)
              _totalsRow(
                'Descuento',
                -quote.discountTotal,
                currencyFormat,
                valueColor: PdfColors.red,
              ),
            if (quote.itbisEnabled)
              _totalsRow(
                'ITBIS (${(quote.itbisRate * 100).toInt()}%)',
                quote.itbisAmount,
                currencyFormat,
              ),
            pw.Divider(color: PdfColors.teal, thickness: 1),
            _totalsRow('TOTAL', quote.total, currencyFormat, isTotal: true),
          ],
        ),
      ),
    );
  }

  static pw.Widget _totalsRow(
    String label,
    double amount,
    NumberFormat currencyFormat, {
    bool isTotal = false,
    PdfColor? valueColor,
  }) {
    final textStyle = pw.TextStyle(
      fontSize: isTotal ? 11 : 9,
      fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: valueColor,
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: textStyle),
          pw.Text(_formatMoney(currencyFormat, amount), style: textStyle),
        ],
      ),
    );
  }

  static String _formatMoney(NumberFormat currencyFormat, double value) {
    final formatted = currencyFormat.format(value.abs());
    final sign = value < 0 ? '-' : '';
    return '${sign}RD\$ $formatted';
  }

  static String _formatQty(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.toStringAsFixed(0);
    }
    return qty.toStringAsFixed(2);
  }

  static String _joinParts(List<String> parts, {String separator = ' '}) {
    final filtered = parts.where((part) => part.trim().isNotEmpty).toList();
    return filtered.join(separator);
  }

  static Future<void> showPreview({
    required BuildContext context,
    required QuoteModel quote,
    required List<QuoteItemModel> items,
    required String clientName,
    String? clientPhone,
    String? clientRnc,
    dynamic business,
    int validDays = 15,
  }) async {
    final displayId = quote.id != null
        ? quote.id!.toString().padLeft(5, '0')
        : '-----';

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileId = quote.id ?? timestamp;
    final fileName = 'cotizacion_${fileId}_$timestamp.pdf';

    final navigator = Navigator.of(context, rootNavigator: true);
    if (!context.mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (context) => _QuotePdfPreviewPage(
          title: 'Cotizacion #COT-$displayId',
          fileName: fileName,
          quote: quote,
          items: items,
          clientName: clientName,
          clientPhone: clientPhone,
          clientRnc: clientRnc,
          business: business,
          validDays: validDays,
        ),
      ),
    );
  }

  static Future<bool> printQuote({
    required QuoteModel quote,
    required List<QuoteItemModel> items,
    required String clientName,
    String? clientPhone,
    String? clientRnc,
    dynamic business,
    required PrinterSettingsModel settings,
    int validDays = 15,
  }) async {
    try {
      final pdfData = await generatePdf(
        quote: quote,
        items: items,
        clientName: clientName,
        clientPhone: clientPhone,
        clientRnc: clientRnc,
        business: business,
        validDays: validDays,
      );

      final printers = await Printing.listPrinters();
      final selectedPrinter = printers.firstWhere(
        (p) => p.name == settings.selectedPrinterName,
        orElse: () => printers.first,
      );

      return await Printing.directPrintPdf(
        printer: selectedPrinter,
        onLayout: (_) => pdfData,
      );
    } catch (e) {
      debugPrint('Error en printQuote: $e');
      return false;
    }
  }
}

class _PdfFonts {
  final pw.Font base;
  final pw.Font bold;

  const _PdfFonts({required this.base, required this.bold});
}

enum _PdfFitMode { width, page }

class _PdfZoomInIntent extends Intent {
  const _PdfZoomInIntent();
}

class _PdfZoomOutIntent extends Intent {
  const _PdfZoomOutIntent();
}

class _PdfResetIntent extends Intent {
  const _PdfResetIntent();
}

class _PdfFitWidthIntent extends Intent {
  const _PdfFitWidthIntent();
}

class _PdfFitPageIntent extends Intent {
  const _PdfFitPageIntent();
}

class _QuotePdfPreviewPage extends StatefulWidget {
  final String title;
  final String fileName;

  final QuoteModel? quote;
  final List<QuoteItemModel>? items;
  final String? clientName;
  final String? clientPhone;
  final String? clientRnc;
  final dynamic business;
  final int validDays;

  const _QuotePdfPreviewPage({
    this.title = '',
    this.fileName = '',
    this.quote,
    this.items,
    this.clientName,
    this.clientPhone,
    this.clientRnc,
    this.business,
    this.validDays = 15,
  });

  @override
  State<_QuotePdfPreviewPage> createState() => _QuotePdfPreviewPageState();
}

class _QuotePdfPreviewPageState extends State<_QuotePdfPreviewPage> {
  final TransformationController _transformController =
      TransformationController();

  Uint8List? _pdfData;
  Object? _loadError;
  bool _loading = false;

  double _zoom = 1.0;
  _PdfFitMode _fitMode = _PdfFitMode.width;
  int _fitRequestId = 0;
  int _fitAppliedRequestId = 0;

  static const double _minZoom = 0.25;
  static const double _maxZoom = 4.0;

  @override
  void initState() {
    super.initState();
    _loadPdf();
    _applyZoom(resetPan: true);
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _pdfData = null;
    });

    final quote = widget.quote;
    final items = widget.items;
    final clientName = widget.clientName;
    if (quote == null || items == null || clientName == null) {
      setState(() {
        _loadError = StateError('Missing quote data for PDF preview.');
        _loading = false;
      });
      return;
    }

    try {
      final data = await QuotePrinter.generatePdf(
        quote: quote,
        items: items,
        clientName: clientName,
        clientPhone: widget.clientPhone,
        clientRnc: widget.clientRnc,
        business: widget.business,
        validDays: widget.validDays,
      );
      if (!mounted) return;
      setState(() => _pdfData = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _setZoom(double newZoom, {bool resetPan = false}) {
    final clamped = newZoom.clamp(_minZoom, _maxZoom);
    if (clamped == _zoom && !resetPan) return;
    setState(() => _zoom = clamped);
    _applyZoom(resetPan: resetPan);
  }

  void _applyZoom({required bool resetPan}) {
    if (resetPan) {
      _transformController.value = Matrix4.identity()..scale(_zoom);
      return;
    }

    final current = _transformController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final factor = currentScale == 0 ? 1.0 : (_zoom / currentScale);
    _transformController.value = current.clone()..scale(factor);
  }

  void _fitToWidth() {
    setState(() {
      _fitMode = _PdfFitMode.width;
      _fitRequestId++;
    });
    _setZoom(1.0, resetPan: true);
  }

  void _fitToPage() {
    setState(() {
      _fitMode = _PdfFitMode.page;
      _fitRequestId++;
    });
  }

  void _resetZoom() {
    _fitToWidth();
  }

  void _zoomIn() => _setZoom(_zoom * 1.10);
  void _zoomOut() => _setZoom(_zoom / 1.10);

  double _computeFitPageZoom(BoxConstraints constraints) {
    final viewportW = constraints.maxWidth;
    final viewportH = constraints.maxHeight;
    if (viewportW <= 0 || viewportH <= 0) return 1.0;

    // Quote PDFs are generated as Letter.
    final aspect = PdfPageFormat.letter.width / PdfPageFormat.letter.height;
    final pageHeightAtFitWidth = viewportW / aspect;
    if (pageHeightAtFitWidth <= 0) return 1.0;

    return (viewportH / pageHeightAtFitWidth).clamp(_minZoom, 1.0);
  }

  void _maybeApplyFit(BoxConstraints constraints) {
    if (_fitRequestId == _fitAppliedRequestId) return;

    // IMPORTANT: this method is invoked from a LayoutBuilder builder.
    // Never call setState synchronously during build.
    final requestId = _fitRequestId;
    final fitMode = _fitMode;
    final maxWidth = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (requestId != _fitRequestId) return;
      if (_fitAppliedRequestId == requestId) return;

      _fitAppliedRequestId = requestId;

      if (fitMode == _PdfFitMode.width) {
        _setZoom(1.0, resetPan: true);
        return;
      }

      final safeConstraints = BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      _setZoom(_computeFitPageZoom(safeConstraints), resetPan: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Volver',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.print),
                    onPressed: (_pdfData == null)
                        ? null
                        : () async {
                            await Printing.layoutPdf(
                              onLayout: (_) => _pdfData!,
                            );
                          },
                    tooltip: 'Imprimir',
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: (_pdfData == null)
                        ? null
                        : () {
                            final bytes = _pdfData;
                            if (bytes == null) return;
                            unawaited(
                              Printing.sharePdf(
                                bytes: bytes,
                                filename: widget.fileName,
                              ),
                            );
                          },
                    tooltip: 'Compartir',
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.fit_screen),
                    onPressed: _fitToWidth,
                    tooltip: 'Ajustar a ancho (Ctrl+1)',
                  ),
                  IconButton(
                    icon: const Icon(Icons.crop_free),
                    onPressed: _fitToPage,
                    tooltip: 'Ajustar a página (Ctrl+2)',
                  ),
                  IconButton(
                    icon: const Icon(Icons.restart_alt),
                    onPressed: _resetZoom,
                    tooltip: 'Reset 100% (Ctrl+0)',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _maybeApplyFit(constraints);

                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (_loadError != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'No se pudo cargar el PDF de la cotización.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _loadPdf,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final data = _pdfData;
                  if (data == null) {
                    return const Center(
                      child: Text('No hay PDF para mostrar.'),
                    );
                  }

                  return Shortcuts(
                    shortcuts: {
                      // Zoom
                      SingleActivator(
                        LogicalKeyboardKey.equal,
                        control: true,
                        shift: true,
                      ): const _PdfZoomInIntent(),
                      SingleActivator(LogicalKeyboardKey.equal, control: true):
                          const _PdfZoomInIntent(),
                      SingleActivator(LogicalKeyboardKey.add, control: true):
                          const _PdfZoomInIntent(),
                      SingleActivator(LogicalKeyboardKey.minus, control: true):
                          const _PdfZoomOutIntent(),
                      SingleActivator(
                        LogicalKeyboardKey.numpadSubtract,
                        control: true,
                      ): const _PdfZoomOutIntent(),

                      // Fit/reset
                      SingleActivator(LogicalKeyboardKey.digit0, control: true):
                          const _PdfResetIntent(),
                      SingleActivator(LogicalKeyboardKey.digit1, control: true):
                          const _PdfFitWidthIntent(),
                      SingleActivator(LogicalKeyboardKey.digit2, control: true):
                          const _PdfFitPageIntent(),
                    },
                    child: Actions(
                      actions: {
                        _PdfZoomInIntent: CallbackAction<_PdfZoomInIntent>(
                          onInvoke: (_) {
                            _zoomIn();
                            return null;
                          },
                        ),
                        _PdfZoomOutIntent: CallbackAction<_PdfZoomOutIntent>(
                          onInvoke: (_) {
                            _zoomOut();
                            return null;
                          },
                        ),
                        _PdfResetIntent: CallbackAction<_PdfResetIntent>(
                          onInvoke: (_) {
                            _resetZoom();
                            return null;
                          },
                        ),
                        _PdfFitWidthIntent: CallbackAction<_PdfFitWidthIntent>(
                          onInvoke: (_) {
                            _fitToWidth();
                            return null;
                          },
                        ),
                        _PdfFitPageIntent: CallbackAction<_PdfFitPageIntent>(
                          onInvoke: (_) {
                            _fitToPage();
                            return null;
                          },
                        ),
                      },
                      child: Focus(
                        autofocus: true,
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          panEnabled: _zoom > 1.01,
                          scaleEnabled: false,
                          minScale: _minZoom,
                          maxScale: _maxZoom,
                          boundaryMargin: const EdgeInsets.all(80),
                          clipBehavior: Clip.hardEdge,
                          child: PdfPreview(
                            build: (_) async => data,
                            canChangeOrientation: false,
                            canChangePageFormat: false,
                            allowPrinting: false,
                            allowSharing: false,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
