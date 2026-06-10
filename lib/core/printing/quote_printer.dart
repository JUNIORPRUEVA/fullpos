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
import '../../features/settings/data/theme_settings_repository.dart';
import '../layout/app_shell.dart';
import '../services/empresa_service.dart';

/// Servicio para imprimir, compartir y generar PDF de cotizaciones.
///
/// Diseño profesional, elegante y corporativo con estética FullPOS.
class QuotePrinter {
  QuotePrinter._();

  // ─────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────

  static String _sanitizePdfText(String input) {
    var s = input.replaceAll('\u00A0', ' ');
    s = s
        .replaceAll('\u2022', '-')
        .replaceAll('\u2013', '-')
        .replaceAll('\u2014', '-')
        .replaceAll('\u2026', '...')
        .replaceAll('\u00B7', '-')
        .replaceAll('\u00AD', '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
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

  static String _logoInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'FP';

    if (parts.length == 1) {
      final token = parts.first;
      return token.substring(0, token.length >= 2 ? 2 : 1).toUpperCase();
    }

    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  static String _statusLabel(String status) {
    final normalized = status.trim().toLowerCase();

    switch (normalized) {
      case 'approved':
      case 'aprobada':
      case 'aprobado':
        return 'APROBADA';
      case 'cancelled':
      case 'canceled':
      case 'cancelada':
      case 'cancelado':
        return 'CANCELADA';
      case 'converted':
      case 'convertida':
      case 'convertido':
        return 'CONVERTIDA';
      case 'expired':
      case 'vencida':
      case 'vencido':
        return 'VENCIDA';
      case 'draft':
      case 'borrador':
        return 'BORRADOR';
      default:
        return 'PENDIENTE';
    }
  }

  static PdfColor _statusPdfColor(String status) {
    final normalized = status.trim().toLowerCase();
    switch (normalized) {
      case 'approved':
      case 'aprobada':
      case 'aprobado':
        return PdfColor.fromInt(0xFF16A34A);
      case 'cancelled':
      case 'canceled':
      case 'cancelada':
      case 'cancelado':
        return PdfColor.fromInt(0xFFDC2626);
      case 'converted':
      case 'convertida':
      case 'convertido':
        return PdfColor.fromInt(0xFF2563EB);
      case 'expired':
      case 'vencida':
      case 'vencido':
        return PdfColor.fromInt(0xFFF59E0B);
      case 'draft':
      case 'borrador':
        return PdfColor.fromInt(0xFF6B7280);
      default:
        return PdfColor.fromInt(0xFF2563EB);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BUSINESS DATA
  // ─────────────────────────────────────────────────────────────

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
      'logoPath': '',
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
      normalized['logoPath'] = business.logoPath ?? '';
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
        'logoPath': config.logoPath ?? '',
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
        'logoPath': '',
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

  static Future<Map<String, int>> _loadBrandPalette() async {
    try {
      final repo = ThemeSettingsRepository();
      final theme = await repo.loadThemeSettings();

      return {
        'primary': theme.appBarColor.value,
        'accent': theme.accentColor.value,
        'surface': theme.surfaceColor.value,
        'text': theme.textColor.value,
        'muted': theme.footerTextColor.value,
      };
    } catch (_) {
      return {
        'primary': 0xFF1A56DB,
        'accent': 0xFF2563EB,
        'surface': 0xFFFFFFFF,
        'text': 0xFF0F172A,
        'muted': 0xFF64748B,
      };
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PUBLIC PDF API
  // ─────────────────────────────────────────────────────────────

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
    final brandPalette = await _loadBrandPalette();

    final payload = <String, dynamic>{
      'quote': quote.toMap(),
      'items': items.map((item) => item.toMap()).toList(),
      'clientName': clientName,
      'clientPhone': clientPhone,
      'clientRnc': clientRnc,
      'business': businessData,
      'brand': brandPalette,
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
    final brandData = Map<String, int>.from(payload['brand'] as Map);

    final clientName = payload['clientName'] as String? ?? '';
    final clientPhone = payload['clientPhone'] as String?;
    final clientRnc = payload['clientRnc'] as String?;
    final validDays = payload['validDays'] as int? ?? 15;

    final fonts = await _loadPdfFonts();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
    );

    final brand = _QuotePdfBrand.fromMap(brandData);

    final safeBusiness = <String, String>{
      for (final entry in businessData.entries)
        entry.key: entry.key == 'logoPath'
            ? entry.value.trim()
            : _sanitizePdfText(entry.value),
    };

    final safeClientName = _sanitizePdfText(clientName);
    final safeClientPhone = clientPhone == null
        ? null
        : _sanitizePdfText(clientPhone);
    final safeClientRnc =
        clientRnc == null ? null : _sanitizePdfText(clientRnc);

    final createdDate = DateTime.fromMillisecondsSinceEpoch(quote.createdAtMs);
    final expirationDate = createdDate.add(Duration(days: validDays));

    final issueDate = DateFormat('dd/MM/yyyy').format(createdDate);
    final validUntil = DateFormat('dd/MM/yyyy').format(expirationDate);

    final currencyFormat = NumberFormat('#,##0.00', 'en_US');
    final logoProvider = await _loadCompanyLogo(safeBusiness['logoPath'] ?? '');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(44, 40, 44, 42),
        footer: (context) => _buildFooter(
          context: context,
          businessData: safeBusiness,
          quote: quote,
          validDays: validDays,
          notes: quote.notes,
          brand: brand,
        ),
        build: (context) {
          final resolvedClientName = safeClientName.trim().isEmpty
              ? 'Consumidor Final'
              : safeClientName.trim();

          return [
            _buildHeader(
              safeBusiness,
              quote,
              issueDate,
              validUntil,
              brand,
              logoProvider,
            ),
            pw.SizedBox(height: 22),
            _buildClientSection(
              clientName: resolvedClientName,
              clientPhone: safeClientPhone,
              clientRnc: safeClientRnc,
              brand: brand,
            ),
            pw.SizedBox(height: 24),
            _buildSectionTitle(
              title: 'Detalle de productos y servicios',
              subtitle: 'Precios expresados en pesos dominicanos (RD\$)',
              brand: brand,
            ),
            pw.SizedBox(height: 10),
            _buildProductsTable(
              quote,
              items,
              currencyFormat,
              brand,
            ),
            pw.SizedBox(height: 22),
            _buildSummarySection(
              quote: quote,
              currencyFormat: currencyFormat,
              brand: brand,
            ),
            pw.SizedBox(height: 22),
            _buildNotesSection(
              notes: quote.notes,
              brand: brand,
            ),
          ];
        },
      ),
    );
    return pdf.save();
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

      if (printers.isEmpty) {
        debugPrint('No hay impresoras disponibles.');
        return false;
      }

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
          title: 'Cotización #COT-$displayId',
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

  // ─────────────────────────────────────────────────────────────
  // FONTS / LOGO
  // ─────────────────────────────────────────────────────────────

  static Future<_PdfFonts> _loadPdfFonts() async {
    try {
      if (Platform.isWindows) {
        final regular = File(r'C:\Windows\Fonts\segoeui.ttf');
        final bold = File(r'C:\Windows\Fonts\segoeuib.ttf');

        if (regular.existsSync() && bold.existsSync()) {
          return _PdfFonts(
            base: pw.Font.ttf(ByteData.view(regular.readAsBytesSync().buffer)),
            bold: pw.Font.ttf(ByteData.view(bold.readAsBytesSync().buffer)),
          );
        }

        final arial = File(r'C:\Windows\Fonts\arial.ttf');
        final arialBold = File(r'C:\Windows\Fonts\arialbd.ttf');

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

  static Future<pw.ImageProvider?> _loadCompanyLogo(String logoPath) async {
    final path = logoPath.trim();

    if (path.isEmpty || kIsWeb) return null;

    try {
      final file = File(path);

      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) return null;

      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PDF SECTIONS — PLANTILLA LIMPIA, EJECUTIVA Y PRINT-FRIENDLY
  // ─────────────────────────────────────────────────────────────

  static pw.Widget _buildHeader(
    Map<String, String> businessData,
    QuoteModel quote,
    String issueDate,
    String validUntil,
    _QuotePdfBrand brand,
    pw.ImageProvider? logoProvider,
  ) {
    final displayId = quote.id != null
        ? quote.id!.toString().padLeft(5, '0')
        : '-----';

    final companyName = (businessData['name'] ?? '').trim().isEmpty
        ? 'FULLPOS'
        : businessData['name']!.trim();

    final address = _joinParts([
      businessData['address'] ?? '',
      businessData['city'] ?? '',
    ], separator: ', ');

    final phones = _joinParts([
      businessData['phone'] ?? '',
      businessData['phone2'] ?? '',
    ], separator: ' / ');

    final statusLabel = _statusLabel(quote.status);
    final statusColor = _statusPdfColor(quote.status);

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 18),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: brand.border, width: 0.9),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Logo
          pw.Container(
            width: 58,
            height: 58,
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: brand.border, width: 0.7),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: logoProvider != null
                ? pw.ClipRRect(
                    horizontalRadius: 9,
                    verticalRadius: 9,
                    child: pw.Image(logoProvider, fit: pw.BoxFit.contain),
                  )
                : pw.Center(
                    child: pw.Text(
                      _logoInitials(companyName),
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: brand.primary,
                      ),
                    ),
                  ),
          ),
          pw.SizedBox(width: 14),
          // Company info (left)
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  companyName,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                    color: brand.text,
                    letterSpacing: -0.2,
                  ),
                ),
                pw.SizedBox(height: 7),
                if (address.isNotEmpty) _headerDetailLine(address, brand),
                if (phones.isNotEmpty) _headerDetailLine('Tel: $phones', brand),
                if ((businessData['rnc'] ?? '').trim().isNotEmpty)
                  _headerDetailLine('RNC: ${businessData['rnc']!}', brand),
                if ((businessData['email'] ?? '').trim().isNotEmpty)
                  _headerDetailLine(businessData['email']!, brand),
              ],
            ),
          ),
          pw.SizedBox(width: 18),
          // Quote info (right)
          pw.Container(
            width: 175,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'COTIZACIÓN',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: brand.text,
                    letterSpacing: 0.4,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '#COT-$displayId',
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: brand.primary,
                  ),
                ),
                pw.SizedBox(height: 10),
                _metaLine('Emisión', issueDate, brand),
                _metaLine('Válida hasta', validUntil, brand),
                pw.SizedBox(height: 7),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: pw.BoxDecoration(
                    color: brand.softPrimary,
                    border: pw.Border.all(color: statusColor, width: 0.6),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Text(
                    statusLabel,
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: statusColor,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _headerDetailLine(String text, _QuotePdfBrand brand) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text(
        text,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: 8.4,
          color: brand.muted,
          height: 1.2,
        ),
      ),
    );
  }

  static pw.Widget _metaLine(String label, String value, _QuotePdfBrand brand) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            '$label  ',
            style: pw.TextStyle(fontSize: 8.1, color: brand.muted),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.1,
              color: brand.text,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildClientSection({
    required String clientName,
    required String? clientPhone,
    required String? clientRnc,
    required _QuotePdfBrand brand,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: pw.BoxDecoration(
        color: brand.surfaceAlt,
        border: pw.Border.all(color: brand.border, width: 0.7),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionCaption('INFORMACIÓN DEL CLIENTE', brand),
          pw.SizedBox(height: 9),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 5,
                child: _clientField('Cliente', clientName, brand),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                flex: 3,
                child: _clientField(
                  'Teléfono',
                  (clientPhone ?? '').trim().isEmpty
                      ? '000-000-0000'
                      : clientPhone!.trim(),
                  brand,
                ),
              ),
              if ((clientRnc ?? '').trim().isNotEmpty) ...[
                pw.SizedBox(width: 16),
                pw.Expanded(
                  flex: 3,
                  child: _clientField('RNC / Cédula', clientRnc!.trim(), brand),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionCaption(String text, _QuotePdfBrand brand) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 8.1,
        fontWeight: pw.FontWeight.bold,
        color: brand.primary,
        letterSpacing: 0.7,
      ),
    );
  }

  static pw.Widget _clientField(String label, String value, _QuotePdfBrand brand) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 7.4, color: brand.muted),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          value,
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(
            fontSize: 9.8,
            color: brand.text,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSectionTitle({
    required String title,
    required String subtitle,
    required _QuotePdfBrand brand,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 12.2,
            fontWeight: pw.FontWeight.bold,
            color: brand.text,
            letterSpacing: -0.15,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          subtitle,
          style: pw.TextStyle(fontSize: 7.6, color: brand.muted),
        ),
      ],
    );
  }

  static pw.Widget _buildProductsTable(
    QuoteModel quote,
    List<QuoteItemModel> items,
    NumberFormat currencyFormat,
    _QuotePdfBrand brand,
  ) {
    final showItbis = quote.itbisEnabled && quote.itbisAmount > 0;

    // Build header cells
    final headerCells = <pw.Widget>[
      _tableHeaderCell('Producto / Servicio', brand),
      _tableHeaderCell('Cant.', brand, align: pw.TextAlign.center),
      _tableHeaderCell('Precio', brand, align: pw.TextAlign.right),
    ];
    if (showItbis) {
      headerCells.add(
        _tableHeaderCell('ITBIS', brand, align: pw.TextAlign.right),
      );
    }
    headerCells.add(
      _tableHeaderCell('Total', brand, align: pw.TextAlign.right),
    );

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: brand.tableHeader),
        children: headerCells,
      ),
    ];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final itemItbis = showItbis && quote.subtotal > 0
          ? (item.totalLine / quote.subtotal) * quote.itbisAmount
          : 0.0;

      final bodyCells = <pw.Widget>[
        _productDescriptionCell(item, brand),
        _tableBodyCell(
          _formatQty(item.qty),
          brand,
          align: pw.TextAlign.center,
          bold: true,
        ),
        _tableBodyCell(
          _formatMoney(currencyFormat, item.price),
          brand,
          align: pw.TextAlign.right,
        ),
      ];
      if (showItbis) {
        bodyCells.add(
          _tableBodyCell(
            itemItbis > 0 ? _formatMoney(currencyFormat, itemItbis) : '-',
            brand,
            align: pw.TextAlign.right,
            muted: itemItbis <= 0,
          ),
        );
      }
      bodyCells.add(
        _tableBodyCell(
          _formatMoney(currencyFormat, item.totalLine),
          brand,
          align: pw.TextAlign.right,
          bold: true,
        ),
      );

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isOdd ? brand.surfaceAlt : PdfColors.white,
          ),
          children: bodyCells,
        ),
      );
    }

    // Column widths: adjust when ITBIS is hidden
    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(4.15),
      1: const pw.FlexColumnWidth(0.8),
      2: const pw.FlexColumnWidth(1.25),
    };
    if (showItbis) {
      columnWidths[3] = const pw.FlexColumnWidth(1.15);
      columnWidths[4] = const pw.FlexColumnWidth(1.35);
    } else {
      columnWidths[3] = const pw.FlexColumnWidth(1.8);
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: brand.border, width: 0.7),
        borderRadius: pw.BorderRadius.circular(9),
      ),
      child: pw.Table(
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: brand.border, width: 0.45),
        ),
        columnWidths: columnWidths,
        children: rows,
      ),
    );
  }

  static pw.Widget _tableHeaderCell(
    String text,
    _QuotePdfBrand brand, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 7.8,
          color: brand.muted,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static pw.Widget _tableBodyCell(
    String text,
    _QuotePdfBrand brand, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    bool muted = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9.5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8.6,
          color: muted ? brand.muted : brand.text,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _productDescriptionCell(
    QuoteItemModel item,
    _QuotePdfBrand brand,
  ) {
    final cleanDescription = _sanitizePdfText(item.description);
    final cleanCode = item.productCode == null
        ? ''
        : _sanitizePdfText(item.productCode!);

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            cleanDescription.isEmpty ? 'Producto / servicio' : cleanDescription,
            maxLines: 3,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              fontSize: 8.9,
              fontWeight: pw.FontWeight.bold,
              color: brand.text,
            ),
          ),
          if (cleanCode.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'Código: $cleanCode',
              style: pw.TextStyle(fontSize: 7.2, color: brand.muted),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildSummarySection({
    required QuoteModel quote,
    required NumberFormat currencyFormat,
    required _QuotePdfBrand brand,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Spacer(),
        _buildTotalsCard(quote, currencyFormat, brand),
      ],
    );
  }

  static pw.Widget _buildTotalsCard(
    QuoteModel quote,
    NumberFormat currencyFormat,
    _QuotePdfBrand brand,
  ) {
    final showItbis = quote.itbisEnabled && quote.itbisAmount > 0;

    return pw.Container(
      width: 245,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: brand.border, width: 0.7),
        borderRadius: pw.BorderRadius.circular(9),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: pw.Text(
              'Resumen',
              style: pw.TextStyle(
                fontSize: 9,
                color: brand.muted,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14),
            child: pw.Column(
              children: [
                _totalsRow('Subtotal', quote.subtotal, currencyFormat, brand),
                if (quote.discountTotal > 0)
                  _totalsRow(
                    'Descuento',
                    -quote.discountTotal,
                    currencyFormat,
                    brand,
                    valueColor: brand.danger,
                  ),
                if (showItbis)
                  _totalsRow(
                    'ITBIS (${(quote.itbisRate * 100).toInt()}%)',
                    quote.itbisAmount,
                    currencyFormat,
                    brand,
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 9),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: pw.BoxDecoration(
              color: brand.primary,
              borderRadius: const pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(8),
                bottomRight: pw.Radius.circular(8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: 11.2,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                pw.Text(
                  _formatMoney(currencyFormat, quote.total),
                  style: pw.TextStyle(
                    fontSize: 11.6,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalsRow(
    String label,
    double amount,
    NumberFormat currencyFormat,
    _QuotePdfBrand brand, {
    PdfColor? valueColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8.4, color: brand.muted)),
          pw.Text(
            _formatMoney(currencyFormat, amount),
            style: pw.TextStyle(
              fontSize: 8.7,
              fontWeight: pw.FontWeight.bold,
              color: valueColor ?? brand.text,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildNotesSection({
    required String? notes,
    required _QuotePdfBrand brand,
  }) {
    final noteText = notes != null ? _sanitizePdfText(notes) : '';

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: brand.surfaceAlt,
        border: pw.Border.all(color: brand.border, width: 0.65),
        borderRadius: pw.BorderRadius.circular(9),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionCaption('NOTAS Y CONDICIONES', brand),
          pw.SizedBox(height: 8),
          pw.Text(
            noteText.isEmpty
                ? 'Esta cotización está sujeta a disponibilidad, condiciones de entrega y confirmación de pago.'
                : noteText,
            style: pw.TextStyle(
              fontSize: 8.3,
              color: brand.muted,
              height: 1.32,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter({
    required pw.Context context,
    required Map<String, String> businessData,
    required QuoteModel quote,
    required int validDays,
    required String? notes,
    required _QuotePdfBrand brand,
  }) {
    const footerHeight = 32.0;

    if (context.pageNumber != context.pagesCount) {
      return pw.SizedBox(height: footerHeight);
    }

    final phone = (businessData['phone'] ?? '').trim();
    final companyName = (businessData['name'] ?? 'FULLPOS').trim();

    return pw.SizedBox(
      height: footerHeight,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Container(height: 0.7, color: brand.border),
          pw.SizedBox(height: 7),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Gracias por su preferencia',
                  style: pw.TextStyle(
                    fontSize: 7.6,
                    color: brand.text,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                phone.isEmpty ? companyName : '$companyName  •  $phone',
                style: pw.TextStyle(fontSize: 7.2, color: brand.muted),
              ),
              pw.SizedBox(width: 10),
              pw.Text(
                'Generado por FullPOS',
                style: pw.TextStyle(fontSize: 7.2, color: brand.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────
// BRAND PALETTE
// ─────────────────────────────────────────────────────────────

class _QuotePdfBrand {
  final PdfColor primary;
  final PdfColor accent;
  final PdfColor text;
  final PdfColor muted;
  final PdfColor border;
  final PdfColor divider;
  final PdfColor surfaceAlt;
  final PdfColor softPrimary;
  final PdfColor tableHeader;
  final PdfColor danger;

  const _QuotePdfBrand({
    required this.primary,
    required this.accent,
    required this.text,
    required this.muted,
    required this.border,
    required this.divider,
    required this.surfaceAlt,
    required this.softPrimary,
    required this.tableHeader,
    required this.danger,
  });

  factory _QuotePdfBrand.fromMap(Map<String, int> map) {
    final primaryInt = _ensureReadableOnWhite(
      map['primary'] ?? 0xFF2563EB,
      0xFF2563EB,
      maxLuminance: 0.70,
    );

    final accentInt = _ensureReadableOnWhite(
      map['accent'] ?? 0xFF2563EB,
      0xFF2563EB,
      maxLuminance: 0.74,
    );

    final textInt = _ensureReadableOnWhite(
      map['text'] ?? 0xFF0F172A,
      0xFF0F172A,
    );

    final mutedInt = _ensureReadableOnWhite(
      map['muted'] ?? 0xFF64748B,
      0xFF64748B,
    );

    final primary = _pdfColorFromInt(primaryInt);
    final accent = _pdfColorFromInt(accentInt);

    return _QuotePdfBrand(
      primary: primary,
      accent: accent,
      text: _pdfColorFromInt(textInt),
      muted: _pdfColorFromInt(mutedInt),
      border: _pdfColorFromInt(0xFFE2E8F0),
      divider: accent,
      surfaceAlt: _pdfColorFromInt(0xFFF8FAFC),
      softPrimary: _pdfColorFromInt(0xFFEFF6FF),
      tableHeader: _pdfColorFromInt(0xFFF1F5F9),
      danger: _pdfColorFromInt(0xFFDC2626),
    );
  }
}

int _ensureReadableOnWhite(
  int color,
  int fallback, {
  double maxLuminance = 0.78,
}) {
  final r = (color >> 16) & 0xFF;
  final g = (color >> 8) & 0xFF;
  final b = color & 0xFF;

  final luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;

  if (luminance > maxLuminance) {
    return fallback;
  }

  return color;
}

PdfColor _pdfColorFromInt(int value) {
  final red = ((value >> 16) & 0xFF) / 255;
  final green = ((value >> 8) & 0xFF) / 255;
  final blue = (value & 0xFF) / 255;

  return PdfColor(red, green, blue);
}

class _PdfFonts {
  final pw.Font base;
  final pw.Font bold;

  const _PdfFonts({required this.base, required this.bold});
}

// ─────────────────────────────────────────────────────────────
// PDF PREVIEW PAGE — Diseño elegante y corporativo
// ─────────────────────────────────────────────────────────────

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
  Uint8List? _pdfData;
  Object? _loadError;
  bool _loading = false;

  double _previewZoom = 1.05;

  @override
  void initState() {
    super.initState();
    _loadPdf();
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

      setState(() {
        _pdfData = data;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadError = e;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _zoomInPreview() {
    setState(() {
      _previewZoom = (_previewZoom + 0.10).clamp(0.75, 1.80);
    });
  }

  void _zoomOutPreview() {
    setState(() {
      _previewZoom = (_previewZoom - 0.10).clamp(0.75, 1.80);
    });
  }

  void _resetPreviewZoom() {
    setState(() {
      _previewZoom = 1.05;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPreviewHeader(),
          const SizedBox(height: 12),
          Expanded(child: _buildPreviewBody()),
        ],
      ),
    );
  }

  Widget _buildPreviewHeader() {
    return Material(
      color: Colors.white.withOpacity(0.98),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.98),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Volver',
              color: const Color(0xFF0F172A),
              splashRadius: 20,
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
                  color: Color(0xFF0F172A),
                  height: 1.1,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildPreviewHeaderIcon(
              icon: Icons.print_rounded,
              tooltip: 'Imprimir cotización',
              onTap: (_pdfData == null)
                  ? null
                  : () async {
                      await Printing.layoutPdf(onLayout: (_) => _pdfData!);
                    },
            ),
            const SizedBox(width: 8),
            _buildPreviewHeaderIcon(
              icon: Icons.share_rounded,
              tooltip: 'Compartir cotización',
              onTap: (_pdfData == null)
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBody() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
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
                    const Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 42,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No se pudo cargar el PDF de la cotización.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
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
            return const Center(child: Text('No hay PDF para mostrar.'));
          }

          final baseWidth = (constraints.maxWidth * 0.50).clamp(560.0, 860.0);
          final pageWidth = (baseWidth * _previewZoom).clamp(460.0, 1250.0);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Alejar',
                        onPressed: _zoomOutPreview,
                        icon: const Icon(Icons.remove_rounded, size: 17),
                        splashRadius: 16,
                        color: const Color(0xFF334155),
                      ),
                      Text(
                        '${(_previewZoom * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Acercar',
                        onPressed: _zoomInPreview,
                        icon: const Icon(Icons.add_rounded, size: 17),
                        splashRadius: 16,
                        color: const Color(0xFF334155),
                      ),
                      IconButton(
                        tooltip: 'Restablecer',
                        onPressed: _resetPreviewZoom,
                        icon: const Icon(
                          Icons.center_focus_strong_rounded,
                          size: 16,
                        ),
                        splashRadius: 16,
                        color: const Color(0xFF334155),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: PdfPreview(
                    build: (_) async => data,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    allowPrinting: false,
                    allowSharing: false,
                    canDebug: false,
                    useActions: false,
                    maxPageWidth: pageWidth,
                    padding: EdgeInsets.zero,
                    scrollViewDecoration: const BoxDecoration(
                      color: Color(0xFFF2F6F9),
                    ),
                    pdfPreviewPageDecoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 20,
                          spreadRadius: -6,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPreviewHeaderIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isDisabled
                ? const Color(0xFFF1F5F9)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isDisabled
                ? const Color(0xFFCBD5E1)
                : const Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }
}
