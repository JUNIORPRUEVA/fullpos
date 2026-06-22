import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/currency_display.dart';
import '../../features/facturacion_electronica/data/factura_electronica_repository.dart';
import '../../features/sales/data/sales_model.dart';
import '../../features/settings/data/business_settings_model.dart';
import '../../features/settings/data/printer_settings_repository.dart';

class InvoiceLetterPdf {
  InvoiceLetterPdf._();

  static String _sanitize(String input) {
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

  static PdfColor _toPdfColor(int value) {
    final a = (value >> 24) & 0xFF;
    final r = (value >> 16) & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = value & 0xFF;
    final alpha = a / 255.0;
    return PdfColor(r / 255.0, g / 255.0, b / 255.0, alpha);
  }

  static String _fmtMoney(String symbol, double amount) {
    return '$symbol ${CurrencyDisplay.formatPlain(amount, decimalDigits: 2)}';
  }

  static String _fmtQty(double qty) {
    final isInt = (qty - qty.roundToDouble()).abs() < 1e-9;
    return isInt ? qty.toStringAsFixed(0) : qty.toStringAsFixed(2);
  }

  static Future<Uint8List> generate({
    required SaleModel sale,
    required List<SaleItemModel> items,
    required BusinessSettings business,
    required int brandColorArgb,
    String? cashierName,
    String? warrantyPolicy,
    String? footerMessage,
  }) async {
    String? resolvedWarrantyPolicy = warrantyPolicy;
    String? resolvedFooterMessage = footerMessage;

    if ((resolvedWarrantyPolicy == null ||
            resolvedWarrantyPolicy.trim().isEmpty) ||
        (resolvedFooterMessage == null ||
            resolvedFooterMessage.trim().isEmpty)) {
      try {
        final printerSettings = await PrinterSettingsRepository.getOrCreate();
        resolvedWarrantyPolicy ??= printerSettings.warrantyPolicy;
        resolvedFooterMessage ??= printerSettings.footerMessage;
      } catch (_) {
        // fallback a valores de negocio si no se puede leer configuración de impresora
      }
    }

    final electronicInvoice = sale.id == null
      ? null
      : await FacturaElectronicaRepository.getBySaleId(sale.id!);

    final brand = _toPdfColor(brandColorArgb);
    final gray700 = PdfColor(0.25, 0.28, 0.32);
    final gray500 = PdfColor(0.42, 0.45, 0.50);
    final gray300 = PdfColor(0.83, 0.85, 0.88);
    final gray100 = PdfColor(0.95, 0.96, 0.97);

    final currencySymbol = (business.currencySymbol).trim().isNotEmpty
        ? business.currencySymbol.trim()
        : 'RD\$';

    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final createdAt = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);

    Uint8List? logoBytes;
    final logoPath = (business.logoPath ?? '').trim();
    if (logoPath.isNotEmpty) {
      try {
        final file = File(logoPath);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) logoBytes = bytes;
        }
      } catch (_) {
        // ignore
      }
    }

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
        build: (context) {
          final rows = <List<String>>[];
          for (final it in items) {
            rows.add([
              _fmtQty(it.qty),
              _sanitize(it.productNameSnapshot),
              _fmtMoney(currencySymbol, it.unitPrice),
              _fmtMoney(currencySymbol, it.totalLine),
            ]);
          }

          // ── Company info ──
          final companyLines = <String>[];
          final name = business.businessName.trim().isNotEmpty
              ? business.businessName.trim()
              : 'FULLPOS';
          companyLines.add(_sanitize(name));

          final slogan = (business.slogan ?? '').trim();
          if (slogan.isNotEmpty) companyLines.add(_sanitize(slogan));

          final rnc = (business.rnc ?? '').trim();
          if (rnc.isNotEmpty) companyLines.add('RNC: ${_sanitize(rnc)}');

          final phone = (business.phone ?? '').trim();
          final phone2 = (business.phone2 ?? '').trim();
          if (phone.isNotEmpty) companyLines.add('Tel: ${_sanitize(phone)}');
          if (phone2.isNotEmpty && phone2 != phone) {
            companyLines.add('Tel 2: ${_sanitize(phone2)}');
          }

          final address = (business.address ?? '').trim();
          final city = (business.city ?? '').trim();
          if (address.isNotEmpty) {
            companyLines.add(_sanitize(address));
          }
          if (city.isNotEmpty) {
            companyLines.add(_sanitize(city));
          }

          final email = (business.email ?? '').trim();
          if (email.isNotEmpty) {
            companyLines.add(_sanitize(email));
          }

          final website = (business.website ?? '').trim();
          final instagram = (business.instagramUrl ?? '').trim();
          final facebook = (business.facebookUrl ?? '').trim();

          final footerParts = <String>[];
          if (website.isNotEmpty) {
            footerParts.add('Web: ${_sanitize(website)}');
          }
          if (instagram.isNotEmpty) {
            footerParts.add('Instagram: ${_sanitize(instagram)}');
          }
          if (facebook.isNotEmpty) {
            footerParts.add('Facebook: ${_sanitize(facebook)}');
          }

          // ── Client info ──
          final clientLines = <String>[];
          final clientName = (sale.customerNameSnapshot ?? '').trim();
          if (clientName.isNotEmpty) clientLines.add(_sanitize(clientName));

          final clientPhone = (sale.customerPhoneSnapshot ?? '').trim();
          if (clientPhone.isNotEmpty) {
            clientLines.add('Tel: ${_sanitize(clientPhone)}');
          }

          final clientRnc = (sale.customerRncSnapshot ?? '').trim();
          if (clientRnc.isNotEmpty) {
            clientLines.add('RNC/Cédula: ${_sanitize(clientRnc)}');
          }

          final bool hasFiscalReceipt =
              (sale.ncfFull ?? '').trim().isNotEmpty ||
              (sale.fiscalReceiptName ?? '').trim().isNotEmpty ||
              (sale.ncfType ?? '').trim().isNotEmpty;

          final String invoiceTitle;
          if ((electronicInvoice?.ecf ?? '').trim().isNotEmpty) {
            invoiceTitle = 'FACTURA ELECTRÓNICA (e-CF)';
          } else if (hasFiscalReceipt) {
            invoiceTitle = 'COMPROBANTE FISCAL';
          } else {
            invoiceTitle = 'FACTURA DE VENTA';
          }

          final warrantyText = (resolvedWarrantyPolicy ?? '').trim();
          final termsText = (resolvedFooterMessage ?? '').trim();

          // ── Helper: section title ──
          pw.Widget sectionTitle(String text) {
            return pw.Text(
              text,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: brand,
                letterSpacing: 0.8,
              ),
            );
          }

          // ── Helper: info line ──
          pw.Widget infoLine(String label, String value) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    label,
                    style: pw.TextStyle(fontSize: 9, color: gray500),
                  ),
                  pw.Text(
                    value,
                    style: pw.TextStyle(fontSize: 9, color: gray700),
                  ),
                ],
              ),
            );
          }

          return [
            // ═══════════════════════════════════════════════════
            //  HEADER
            // ═══════════════════════════════════════════════════
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Logo (only if real content exists)
                if (logoBytes != null)
                  pw.Container(
                    width: 52,
                    height: 52,
                    margin: const pw.EdgeInsets.only(right: 14),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                // Company info
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        name,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: gray700,
                        ),
                      ),
                      if (slogan.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(
                            slogan,
                            style: pw.TextStyle(
                              fontSize: 9,
                              color: gray500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Invoice title and metadata
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: pw.BoxDecoration(
                        color: brand,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        invoiceTitle,
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'No. ${_sanitize(sale.localCode)}',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: gray700,
                      ),
                    ),
                    pw.Text(
                      dateFmt.format(createdAt),
                      style: pw.TextStyle(fontSize: 9, color: gray500),
                    ),
                    if (cashierName != null && cashierName.trim().isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: pw.Text(
                          'Cajero: ${_sanitize(cashierName)}',
                          style: pw.TextStyle(fontSize: 9, color: gray500),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 20),

            // ═══════════════════════════════════════════════════
            //  COMPANY DETAILS + CLIENT INFO (side by side)
            // ═══════════════════════════════════════════════════
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Company details
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      sectionTitle('EMISOR'),
                      pw.SizedBox(height: 6),
                      ...companyLines.map(
                        (line) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Text(
                            line,
                            style: pw.TextStyle(fontSize: 9, color: gray700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 24),
                // Client info
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      sectionTitle('CLIENTE'),
                      pw.SizedBox(height: 6),
                      if (clientLines.isEmpty)
                        pw.Text(
                          'Consumidor final',
                          style: pw.TextStyle(fontSize: 9, color: gray500),
                        )
                      else
                        ...clientLines.map(
                          (line) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 2),
                            child: pw.Text(
                              line,
                              style: pw.TextStyle(fontSize: 9, color: gray700),
                            ),
                          ),
                        ),
                      // Electronic invoice e-CF block (only for e-invoice)
                      if ((electronicInvoice?.ecf ?? '').trim().isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: gray100,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'e-CF:',
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                  color: brand,
                                ),
                              ),
                              pw.Text(
                                _sanitize(electronicInvoice!.ecf!.trim()),
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                  color: brand,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if ((electronicInvoice.mensajeDgii ?? '').trim().isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 6),
                            child: pw.Text(
                              _sanitize(electronicInvoice.mensajeDgii!.trim()),
                              style: pw.TextStyle(
                                fontSize: 8,
                                color: brand,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 22),

            // ═══════════════════════════════════════════════════
            //  PRODUCTS TABLE
            // ═══════════════════════════════════════════════════
            sectionTitle('PRODUCTOS'),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerDecoration: pw.BoxDecoration(
                color: gray100,
                border: pw.Border(
                  bottom: pw.BorderSide(color: gray300),
                ),
              ),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: gray700,
              ),
              cellStyle: pw.TextStyle(fontSize: 9, color: gray700),
              cellAlignments: {
                0: pw.Alignment.centerRight,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FixedColumnWidth(72),
                3: const pw.FixedColumnWidth(72),
              },
              headers: const ['Cant.', 'Descripción', 'Precio', 'Importe'],
              data: rows,
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: gray100),
              ),
            ),

            pw.SizedBox(height: 22),

            // ═══════════════════════════════════════════════════
            //  TOTALS + OBSERVATIONS
            // ═══════════════════════════════════════════════════
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Observations (if any)
                if (business.receiptHeader.trim().isNotEmpty) ...[
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        sectionTitle('OBSERVACIONES'),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          _sanitize(business.receiptHeader.trim()),
                          style: pw.TextStyle(fontSize: 9, color: gray700),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 24),
                ] else ...[
                  pw.Spacer(),
                ],
                // Totals
                pw.Container(
                  width: 220,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _totLine(
                        'Subtotal',
                        _fmtMoney(currencySymbol, sale.subtotal),
                        gray700, gray500,
                      ),
                      _totLine(
                        'Descuento',
                        _fmtMoney(currencySymbol, sale.discountTotal),
                        gray700, gray500,
                      ),
                      if (sale.itbisEnabled == 1)
                        _totLine(
                          'ITBIS',
                          _fmtMoney(currencySymbol, sale.itbisAmount),
                          gray700, gray500,
                        ),
                      pw.Divider(color: gray300, height: 16),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'TOTAL',
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: gray700,
                            ),
                          ),
                          pw.Text(
                            _fmtMoney(currencySymbol, sale.total),
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: gray700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ═══════════════════════════════════════════════════
            //  FISCAL RECEIPT BLOCK (local NCF, no e-CF)
            // ═══════════════════════════════════════════════════
            if (hasFiscalReceipt) ...[
              pw.SizedBox(height: 18),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: gray300),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    sectionTitle('COMPROBANTE FISCAL'),
                    pw.SizedBox(height: 6),
                    if ((sale.fiscalReceiptName ?? '').trim().isNotEmpty)
                      infoLine(
                        'Tipo',
                        _sanitize(sale.fiscalReceiptName!.trim()),
                      ),
                    if ((sale.ncfFull ?? '').trim().isNotEmpty)
                      infoLine(
                        'NCF',
                        _sanitize(sale.ncfFull!.trim()),
                      ),
                    if (sale.fiscalReceiptExpirationDateMs != null)
                      infoLine(
                        'Vence',
                        DateFormat('dd/MM/yyyy').format(
                          DateTime.fromMillisecondsSinceEpoch(
                            sale.fiscalReceiptExpirationDateMs!,
                          ),
                        ),
                      ),
                    if ((sale.customerRncSnapshot ?? '').trim().isNotEmpty)
                      infoLine(
                        'RNC/Cédula',
                        _sanitize(sale.customerRncSnapshot!.trim()),
                      ),
                  ],
                ),
              ),
            ],

            pw.SizedBox(height: 18),

            // ═══════════════════════════════════════════════════
            //  FOOTER (social / web links)
            // ═══════════════════════════════════════════════════
            if (footerParts.isNotEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: footerParts
                      .map(
                        (t) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Text(
                            t,
                            style: pw.TextStyle(fontSize: 9, color: gray500),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

            // ═══════════════════════════════════════════════════
            //  WARRANTY POLICY
            // ═══════════════════════════════════════════════════
            if (warrantyText.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: gray100,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'POLÍTICA DE GARANTÍA',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: gray700,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _sanitize(warrantyText),
                      style: pw.TextStyle(fontSize: 9, color: gray700),
                    ),
                  ],
                ),
              ),
            ],

            // ═══════════════════════════════════════════════════
            //  FOOTER MESSAGE
            // ═══════════════════════════════════════════════════
            if (termsText.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Text(
                _sanitize(termsText),
                style: pw.TextStyle(fontSize: 9, color: gray500),
              ),
            ],
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _totLine(
    String label,
    String value,
    PdfColor labelColor,
    PdfColor valueColor,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: labelColor)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, color: valueColor)),
        ],
      ),
    );
  }
}
