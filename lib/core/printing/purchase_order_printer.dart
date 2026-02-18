import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../features/sales/data/business_info_model.dart';
import '../../features/purchases/data/purchase_order_models.dart';

class PurchaseOrderPrinter {
  PurchaseOrderPrinter._();

  static const PdfColor _brandBlue = PdfColor(0.11, 0.23, 0.54);
  static const PdfColor _softBorder = PdfColor(0.87, 0.90, 0.95);
  static const PdfColor _softFill = PdfColor(0.97, 0.98, 1);
  static const PdfColor _noteFill = PdfColor(1, 0.98, 0.90);
  static const PdfColor _noteBorder = PdfColor(0.96, 0.84, 0.45);

  static Future<Uint8List> generatePdf({
    required PurchaseOrderDetailDto detail,
    required BusinessInfoModel business,
  }) async {
    final pdf = pw.Document();

    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    final createdDate = DateTime.fromMillisecondsSinceEpoch(
      detail.order.createdAtMs,
    );
    final purchaseDate = detail.order.purchaseDateMs != null
        ? DateTime.fromMillisecondsSinceEpoch(detail.order.purchaseDateMs!)
        : null;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                business,
                detail,
                dateFormat: dateFormat,
                createdDate: createdDate,
                purchaseDate: purchaseDate,
              ),
              pw.SizedBox(height: 14),
              pw.Divider(thickness: 2, color: _brandBlue),
              pw.SizedBox(height: 14),

              _buildSupplierInfo(detail),
              pw.SizedBox(height: 16),

              _buildItemsTable(detail, currencyFormat),
              pw.SizedBox(height: 24),

              _buildTotals(detail.order, currencyFormat),

              if ((detail.order.notes ?? '').trim().isNotEmpty) ...[
                pw.SizedBox(height: 18),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: _noteFill,
                    border: pw.Border.all(color: _noteBorder, width: 0.8),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'NOTA IMPORTANTE PARA SUPLIDOR:',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: _brandBlue,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        detail.order.notes!.trim(),
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],

              pw.Spacer(),
              pw.Divider(thickness: 1, color: _softBorder),
              pw.SizedBox(height: 6),
              pw.Text(
                'Documento generado por el sistema POS',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> showPreview({
    required BuildContext context,
    required PurchaseOrderDetailDto detail,
    required BusinessInfoModel business,
  }) async {
    final bytes = await generatePdf(detail: detail, business: business);

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: SizedBox(
            width: 900,
            height: 700,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Orden de Compra (PDF)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    key: const ValueKey('purchase_order_pdf_preview_simple'),
                    build: (format) async => bytes,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    allowPrinting: false,
                    allowSharing: false,
                    dynamicLayout: false,
                    dpi: 96,
                    initialPageFormat: PdfPageFormat.letter,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static pw.Widget _buildHeader(
    BusinessInfoModel business,
    PurchaseOrderDetailDto detail,
    {
    required DateFormat dateFormat,
    required DateTime createdDate,
    required DateTime? purchaseDate,
  }
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                business.name,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandBlue,
                ),
              ),
              if ((business.slogan ?? '').trim().isNotEmpty)
                pw.Text(
                  business.slogan!.trim(),
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              pw.SizedBox(height: 6),
              if ((business.phone ?? '').trim().isNotEmpty)
                pw.Text(
                  'Tel: ${business.phone}',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                ),
              if ((business.address ?? '').trim().isNotEmpty)
                pw.Text(
                  business.address!,
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                ),
              if ((business.rnc ?? '').trim().isNotEmpty)
                pw.Text(
                  'RNC: ${business.rnc}',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Container(
          width: 250,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _softFill,
            border: pw.Border.all(color: _brandBlue, width: 1.6),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'DATOS DE LA ORDEN',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandBlue,
                ),
              ),
              pw.SizedBox(height: 6),
              _headerOrderRow(
                'No. Orden',
                detail.order.id != null ? '#${detail.order.id}' : 'N/D',
              ),
              _headerOrderRow('Fecha emisión', dateFormat.format(createdDate)),
              _headerOrderRow(
                'Fecha compra',
                _formatOptionalDate(dateFormat, purchaseDate),
              ),
              _headerOrderRow('Estado', detail.order.status.toUpperCase()),
              _headerOrderRow(
                'Tipo',
                detail.order.isAuto == 1 ? 'AUTOMÁTICA' : 'MANUAL',
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _headerOrderRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 78,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 8.2,
                color: PdfColors.grey800,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8.2),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatOptionalDate(DateFormat dateFormat, DateTime? value) {
    if (value == null) {
      return 'N/D';
    }
    return dateFormat.format(value);
  }

  static pw.Widget _buildSupplierInfo(PurchaseOrderDetailDto detail) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _softFill,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'SUPLIDOR',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(detail.supplierName, style: const pw.TextStyle(fontSize: 10)),
          if ((detail.supplierPhone ?? '').trim().isNotEmpty)
            pw.Text(
              'Tel: ${detail.supplierPhone}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable(
    PurchaseOrderDetailDto detail,
    NumberFormat currencyFormat,
  ) {
    final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );

    pw.Widget cell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Text(
          text,
          style: const pw.TextStyle(fontSize: 9),
          textAlign: align,
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _softBorder, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(6),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _brandBlue),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('CÓDIGO', style: headerStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('PRODUCTO', style: headerStyle),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                'CANT.',
                style: headerStyle,
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                'COSTO',
                style: headerStyle,
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                'TOTAL',
                style: headerStyle,
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
        ...detail.items.map((e) {
          return pw.TableRow(
            children: [
              cell(e.productCode),
              cell(e.productName),
              cell(e.item.qty.toStringAsFixed(2), align: pw.TextAlign.right),
              cell(
                currencyFormat.format(e.item.unitCost),
                align: pw.TextAlign.right,
              ),
              cell(
                currencyFormat.format(e.item.totalLine),
                align: pw.TextAlign.right,
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTotals(
    PurchaseOrderModel order,
    NumberFormat currencyFormat,
  ) {
    pw.Widget row(String label, String value, {bool bold = false}) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      );
    }

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 240,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _softFill,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            row('Subtotal', currencyFormat.format(order.subtotal)),
            pw.SizedBox(height: 4),
            row(
              'Impuesto (${order.taxRate.toStringAsFixed(2)}%)',
              currencyFormat.format(order.taxAmount),
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 6),
            row('TOTAL', currencyFormat.format(order.total), bold: true),
          ],
        ),
      ),
    );
  }
}
