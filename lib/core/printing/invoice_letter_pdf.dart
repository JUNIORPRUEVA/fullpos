import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/currency_display.dart';
import '../../features/facturacion_electronica/data/factura_electronica_repository.dart';
import '../../features/sales/data/sales_model.dart';
import '../../features/sales/data/sale_totals_calculator.dart';
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

  static String _friendlyInvoiceNumber(SaleModel sale) {
    final saleId = sale.id;
    if (saleId != null && saleId > 0) {
      return '#${saleId.toString().padLeft(6, '0')}';
    }

    final code = _sanitize(sale.localCode).trim();
    final numeric = RegExp(r'\d+').allMatches(code).map((m) => m.group(0)!);
    final lastNumber = numeric.isEmpty ? '' : numeric.last;
    if (lastNumber.isNotEmpty) {
      return '#${lastNumber.padLeft(6, '0')}';
    }

    final compact = code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (compact.isEmpty) return '#000000';
    final shortCode = compact.length <= 8
        ? compact
        : compact.substring(compact.length - 8);
    return '#${shortCode.toUpperCase()}';
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
    final ink = PdfColor(0.10, 0.12, 0.16);
    final muted = PdfColor(0.38, 0.42, 0.48);
    final line = PdfColor(0.84, 0.87, 0.91);
    final soft = PdfColor(0.96, 0.98, 1.00);
    final pale = PdfColor(0.98, 0.99, 1.00);

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
          final hasLineDiscount = items.any((it) => it.discountLine > 0.009);
          for (final it in items) {
            final row = <String>[
              _sanitize(it.productNameSnapshot),
              _fmtQty(it.qty),
              _fmtMoney(currencySymbol, it.unitPrice),
            ];
            if (hasLineDiscount) {
              row.add(
                it.discountLine > 0.009
                    ? '-${_fmtMoney(currencySymbol, it.discountLine)}'
                    : _fmtMoney(currencySymbol, 0),
              );
            }
            row.add(_fmtMoney(currencySymbol, it.totalLine));
            rows.add(row);
          }
          final totals = SaleTotalsCalculator.fromDiscountedSubtotal(
            subtotal: sale.subtotal,
            discountTotal: sale.discountTotal,
            itbisEnabled: sale.itbisEnabled == 1,
            itbisRate: sale.itbisRate,
            itbisAmount: sale.itbisAmount,
            total: sale.total,
          );

          final companyLines = <String>[];
          final name = business.businessName.trim().isNotEmpty
              ? business.businessName.trim()
              : 'FULLPOS';

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
          clientLines.add(
            clientName.isNotEmpty ? _sanitize(clientName) : 'Consumidor final',
          );

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
            invoiceTitle = 'FACTURA ELECTRÓNICA';
          } else if (hasFiscalReceipt) {
            invoiceTitle = 'FACTURA FISCAL';
          } else {
            invoiceTitle = 'FACTURA';
          }

          final warrantyText = (resolvedWarrantyPolicy ?? '').trim();
          final termsText = (resolvedFooterMessage ?? '').trim();
          final fiscalLines = <_InfoPair>[
            _InfoPair('Condición', sale.paymentMethodDisplayLabel),
          ];
          if ((sale.fiscalReceiptName ?? '').trim().isNotEmpty) {
            fiscalLines.add(
              _InfoPair('Tipo', _sanitize(sale.fiscalReceiptName!.trim())),
            );
          }
          if ((sale.ncfFull ?? '').trim().isNotEmpty) {
            fiscalLines.add(_InfoPair('NCF', _sanitize(sale.ncfFull!.trim())));
          }
          if ((electronicInvoice?.ecf ?? '').trim().isNotEmpty) {
            fiscalLines.add(
              _InfoPair('e-CF', _sanitize(electronicInvoice!.ecf!.trim())),
            );
          }
          if (sale.fiscalReceiptExpirationDateMs != null) {
            fiscalLines.add(
              _InfoPair(
                'Vence',
                DateFormat('dd/MM/yyyy').format(
                  DateTime.fromMillisecondsSinceEpoch(
                    sale.fiscalReceiptExpirationDateMs!,
                  ),
                ),
              ),
            );
          }

          return [
            _buildHeader(
              logoBytes: logoBytes,
              companyName: name,
              companyLines: companyLines,
              invoiceTitle: invoiceTitle,
              invoiceNumber: _friendlyInvoiceNumber(sale),
              issueDate: dateFmt.format(createdAt),
              cashierName: cashierName,
              brand: brand,
              ink: ink,
              muted: muted,
            ),
            pw.SizedBox(height: 24),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _buildInfoCard(
                    title: 'Facturar a',
                    lines: clientLines,
                    brand: brand,
                    ink: ink,
                    muted: muted,
                    line: line,
                    fill: pale,
                  ),
                ),
                pw.SizedBox(width: 18),
                pw.Expanded(
                  child: _buildFiscalCard(
                    title: 'Datos de facturación',
                    pairs: fiscalLines,
                    brand: brand,
                    ink: ink,
                    muted: muted,
                    line: line,
                    fill: pale,
                  ),
                ),
              ],
            ),
            if ((electronicInvoice?.mensajeDgii ?? '').trim().isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                _sanitize(electronicInvoice!.mensajeDgii!.trim()),
                style: pw.TextStyle(fontSize: 8, color: brand),
              ),
            ],
            pw.SizedBox(height: 24),
            _sectionLabel('Detalle de venta', brand),
            pw.SizedBox(height: 8),
            _buildItemsTable(
              rows: rows,
              hasLineDiscount: hasLineDiscount,
              ink: ink,
              muted: muted,
              line: line,
              soft: soft,
            ),
            pw.SizedBox(height: 22),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (business.receiptHeader.trim().isNotEmpty) ...[
                  pw.Expanded(
                    child: _buildNoteBlock(
                      title: 'Observaciones',
                      text: business.receiptHeader.trim(),
                      brand: brand,
                      ink: ink,
                      muted: muted,
                      line: line,
                    ),
                  ),
                  pw.SizedBox(width: 18),
                ] else ...[
                  pw.Spacer(),
                ],
                _buildTotalsBlock(
                  totals: totals,
                  showItbis: sale.itbisEnabled == 1,
                  currencySymbol: currencySymbol,
                  brand: brand,
                  ink: ink,
                  muted: muted,
                  line: line,
                  fill: soft,
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            if (footerParts.isNotEmpty) ...[
              pw.Divider(color: line, height: 14),
              pw.Text(
                footerParts.join('   |   '),
                style: pw.TextStyle(fontSize: 8.5, color: muted),
              ),
            ],
            if (warrantyText.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              _buildNoteBlock(
                title: 'Política de garantía',
                text: warrantyText,
                brand: brand,
                ink: ink,
                muted: muted,
                line: line,
              ),
            ],
            if (termsText.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Text(
                _sanitize(termsText),
                style: pw.TextStyle(fontSize: 8.5, color: muted),
              ),
            ],
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildHeader({
    required Uint8List? logoBytes,
    required String companyName,
    required List<String> companyLines,
    required String invoiceTitle,
    required String invoiceNumber,
    required String issueDate,
    required String? cashierName,
    required PdfColor brand,
    required PdfColor ink,
    required PdfColor muted,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoBytes != null)
                pw.Container(
                  width: 58,
                  height: 58,
                  margin: const pw.EdgeInsets.only(right: 14),
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Image(
                    pw.MemoryImage(logoBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _sanitize(companyName),
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    ...companyLines.map(
                      (line) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2.5),
                        child: pw.Text(
                          line,
                          style: pw.TextStyle(fontSize: 8.8, color: muted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        pw.Container(
          width: 180,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                invoiceTitle,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: pw.BoxDecoration(
                  color: brand,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Text(
                  'Factura $invoiceNumber',
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              _smallRightLine('Fecha', issueDate, muted, ink),
              if (cashierName != null && cashierName.trim().isNotEmpty)
                _smallRightLine(
                  'Cajero',
                  _sanitize(cashierName.trim()),
                  muted,
                  ink,
                ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _smallRightLine(
    String label,
    String value,
    PdfColor muted,
    PdfColor ink,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.RichText(
        textAlign: pw.TextAlign.right,
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontSize: 8.8, color: muted),
            ),
            pw.TextSpan(
              text: value,
              style: pw.TextStyle(fontSize: 8.8, color: ink),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _sectionLabel(String text, PdfColor brand) {
    return pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
        color: brand,
        letterSpacing: 0.7,
      ),
    );
  }

  static pw.Widget _buildInfoCard({
    required String title,
    required List<String> lines,
    required PdfColor brand,
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor fill,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: fill,
        border: pw.Border(left: pw.BorderSide(color: brand, width: 2.4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel(title, brand),
          pw.SizedBox(height: 8),
          ...lines.map(
            (lineText) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(
                _sanitize(lineText),
                style: pw.TextStyle(
                  fontSize: lineText == lines.first ? 10.2 : 8.8,
                  fontWeight: lineText == lines.first
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  color: lineText == lines.first ? ink : muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFiscalCard({
    required String title,
    required List<_InfoPair> pairs,
    required PdfColor brand,
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor fill,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: fill,
        border: pw.Border.all(color: line, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel(title, brand),
          pw.SizedBox(height: 8),
          ...pairs.map(
            (pair) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    pair.label,
                    style: pw.TextStyle(fontSize: 8.8, color: muted),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Text(
                      pair.value,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8.8,
                        fontWeight: pair.label == 'NCF' || pair.label == 'e-CF'
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable({
    required List<List<String>> rows,
    required bool hasLineDiscount,
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor soft,
  }) {
    final headers = <String>['Descripción', 'Cant.', 'Precio'];
    if (hasLineDiscount) headers.add('Desc.');
    headers.add('Importe');

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerDecoration: pw.BoxDecoration(
        color: soft,
        border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.8)),
      ),
      headerStyle: pw.TextStyle(
        fontSize: 8.7,
        fontWeight: pw.FontWeight.bold,
        color: ink,
      ),
      cellStyle: pw.TextStyle(fontSize: 8.7, color: ink),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        if (hasLineDiscount) 3: pw.Alignment.centerRight,
        if (hasLineDiscount) 4: pw.Alignment.centerRight,
        if (!hasLineDiscount) 3: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FixedColumnWidth(42),
        2: const pw.FixedColumnWidth(74),
        if (hasLineDiscount) 3: const pw.FixedColumnWidth(68),
        if (hasLineDiscount) 4: const pw.FixedColumnWidth(78),
        if (!hasLineDiscount) 3: const pw.FixedColumnWidth(78),
      },
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: line, width: 0.35),
        bottom: pw.BorderSide(color: line, width: 0.6),
      ),
    );
  }

  static pw.Widget _buildTotalsBlock({
    required SaleTotals totals,
    required bool showItbis,
    required String currencySymbol,
    required PdfColor brand,
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
    required PdfColor fill,
  }) {
    return pw.Container(
      width: 235,
      padding: const pw.EdgeInsets.fromLTRB(16, 13, 16, 14),
      decoration: pw.BoxDecoration(
        color: fill,
        border: pw.Border.all(color: line, width: 0.7),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _totLine(
            'Subtotal',
            _fmtMoney(currencySymbol, totals.grossSubtotal),
            muted,
            ink,
          ),
          if (totals.discountTotal > 0.009)
            _totLine(
              'Descuento',
              '-${_fmtMoney(currencySymbol, totals.discountTotal)}',
              muted,
              ink,
            ),
          if (showItbis)
            _totLine(
              'ITBIS',
              _fmtMoney(currencySymbol, totals.itbisAmount),
              muted,
              ink,
            ),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 9),
            height: 0.8,
            color: line,
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total',
                style: pw.TextStyle(
                  fontSize: 13.5,
                  fontWeight: pw.FontWeight.bold,
                  color: brand,
                ),
              ),
              pw.Text(
                _fmtMoney(currencySymbol, totals.total),
                style: pw.TextStyle(
                  fontSize: 13.5,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildNoteBlock({
    required String title,
    required String text,
    required PdfColor brand,
    required PdfColor ink,
    required PdfColor muted,
    required PdfColor line,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: line, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel(title, brand),
          pw.SizedBox(height: 6),
          pw.Text(
            _sanitize(text),
            style: pw.TextStyle(fontSize: 8.7, color: muted, lineSpacing: 2),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totLine(
    String label,
    String value,
    PdfColor labelColor,
    PdfColor valueColor,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9.2, color: labelColor)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9.2, color: valueColor)),
        ],
      ),
    );
  }
}

class _InfoPair {
  final String label;
  final String value;

  const _InfoPair(this.label, this.value);
}
