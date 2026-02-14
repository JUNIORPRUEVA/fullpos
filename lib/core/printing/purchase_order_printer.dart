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

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(business, detail),
              pw.SizedBox(height: 14),
              pw.Divider(thickness: 2, color: PdfColors.teal),
              pw.SizedBox(height: 14),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Fecha: ${dateFormat.format(createdDate)}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  _buildStatusChip(detail.order.status),
                ],
              ),
              pw.SizedBox(height: 14),

              _buildSupplierInfo(detail),
              pw.SizedBox(height: 16),

              _buildItemsTable(detail, currencyFormat),
              pw.SizedBox(height: 16),

              _buildTotals(detail.order, currencyFormat),

              if ((detail.order.notes ?? '').trim().isNotEmpty) ...[
                pw.SizedBox(height: 18),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'NOTAS:',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
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
              pw.Divider(thickness: 1, color: PdfColors.grey400),
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
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              business.name,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.teal,
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
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.teal, width: 2),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'ORDEN DE COMPRA',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '#${detail.order.id ?? '-'}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildStatusChip(String status) {
    final normalized = status.trim().toUpperCase();
    final bg = normalized == 'RECIBIDA'
        ? PdfColors.green100
        : PdfColors.amber100;
    final fg = normalized == 'RECIBIDA'
        ? PdfColors.green900
        : PdfColors.orange900;

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        normalized,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  static pw.Widget _buildSupplierInfo(PurchaseOrderDetailDto detail) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
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
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(6),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.teal),
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
          color: PdfColors.grey100,
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
