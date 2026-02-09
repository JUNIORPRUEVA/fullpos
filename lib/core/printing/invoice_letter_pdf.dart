import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/sales/data/sales_model.dart';
import '../../features/settings/data/business_settings_model.dart';

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
    return '$symbol ${amount.toStringAsFixed(2)}';
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
  }) async {
    final brand = _toPdfColor(brandColorArgb);
    final accent = PdfColors.grey800;

    final currencySymbol = (business.currencySymbol).trim().isNotEmpty
        ? business.currencySymbol.trim()
        : 'RD\$';

    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final createdAt = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);

    Uint8List? logoBytes;
    if (business.showLogoOnReceipt) {
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
    }

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
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

          final String invoiceTitle;
          if (sale.fiscalEnabled == 1 &&
              (sale.ncfFull ?? '').trim().isNotEmpty) {
            invoiceTitle = 'FACTURA (NCF)';
          } else {
            invoiceTitle = 'FACTURA';
          }

          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: brand,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoBytes != null) ...[
                    pw.Container(
                      width: 46,
                      height: 46,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Image(
                        pw.MemoryImage(logoBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                    pw.SizedBox(width: 12),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          invoiceTitle,
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'No. ${_sanitize(sale.localCode)} · ${dateFmt.format(createdAt)}',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (cashierName != null && cashierName.trim().isNotEmpty)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor(1, 1, 1, 0.13),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        _sanitize(cashierName),
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'EMISOR',
                          style: pw.TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        ...companyLines.map(
                          (line) => pw.Text(
                            line,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'CLIENTE',
                          style: pw.TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        if (clientLines.isEmpty)
                          pw.Text(
                            'Consumidor final',
                            style: const pw.TextStyle(fontSize: 10),
                          )
                        else
                          ...clientLines.map(
                            (line) => pw.Text(
                              line,
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        if (sale.fiscalEnabled == 1 &&
                            (sale.ncfFull ?? '').trim().isNotEmpty) ...[
                          pw.SizedBox(height: 8),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.grey100,
                              borderRadius: pw.BorderRadius.circular(6),
                            ),
                            child: pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  'NCF:',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                    color: accent,
                                  ),
                                ),
                                pw.Text(
                                  _sanitize(sale.ncfFull!.trim()),
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                    color: accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 14),

            pw.Text(
              'DETALLE',
              style: pw.TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey200),
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FixedColumnWidth(40),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FixedColumnWidth(74),
                3: const pw.FixedColumnWidth(74),
              },
              headers: const ['Cant.', 'Descripción', 'Precio', 'Importe'],
              data: rows,
              border: pw.TableBorder.all(color: PdfColors.grey300),
            ),

            pw.SizedBox(height: 14),

            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'OBSERVACIONES',
                          style: pw.TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          _sanitize(
                            (business.receiptHeader).trim().isNotEmpty
                                ? business.receiptHeader
                                : '',
                          ),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Container(
                  width: 220,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _totLine(
                        'Subtotal',
                        _fmtMoney(currencySymbol, sale.subtotal),
                      ),
                      _totLine(
                        'Descuento',
                        _fmtMoney(currencySymbol, sale.discountTotal),
                      ),
                      _totLine(
                        'ITBIS',
                        _fmtMoney(currencySymbol, sale.itbisAmount),
                      ),
                      pw.Divider(color: PdfColors.grey400),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'TOTAL',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: accent,
                            ),
                          ),
                          pw.Text(
                            _fmtMoney(currencySymbol, sale.total),
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            if (footerParts.isNotEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: footerParts
                      .map(
                        (t) =>
                            pw.Text(t, style: const pw.TextStyle(fontSize: 9)),
                      )
                      .toList(),
                ),
              ),

            if (business.receiptFooter.trim().isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Text(
                _sanitize(business.receiptFooter.trim()),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _totLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }
}
