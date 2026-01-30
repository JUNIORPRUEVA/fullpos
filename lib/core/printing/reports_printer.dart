import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/services/app_configuration_service.dart';
import '../../features/reports/data/reports_repository.dart';

class ReportsPrinter {
  ReportsPrinter._();

  static Future<Uint8List> generatePdf({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required Map<String, bool> sections,
    required KpisData? kpis,
    required List<SeriesDataPoint> salesSeries,
    required List<SeriesDataPoint> profitSeries,
    required List<PaymentMethodData> paymentMethods,
    required List<TopProduct> topProducts,
    required List<TopClient> topClients,
    required List<SaleRecord> salesList,
    required Map<String, dynamic> comparativeStats,
  }) async {
    final pdf = pw.Document();

    final businessName = appConfigService.getBusinessName().trim();
    final website = appConfigService.getWebsite()?.trim();

    final currencySymbol = appConfigService.getCurrencySymbol().trim();
    final currency = NumberFormat('#,##0.00', 'en_US');
    final date = DateFormat('dd/MM/yyyy');

    pw.Widget sectionTitle(String title) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 8),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.teal100,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.teal900,
          ),
        ),
      );
    }

    pw.Widget kvRow(String label, String value) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(
            flex: 5,
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey900,
              ),
            ),
          ),
        ],
      );
    }

    pw.Widget simpleTable({
      required List<String> headers,
      required List<List<String>> rows,
    }) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: {
          for (var i = 0; i < headers.length; i++)
            i: const pw.FlexColumnWidth(),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              for (final h in headers)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          for (final r in rows)
            pw.TableRow(
              children: [
                for (final c in r)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(c, style: const pw.TextStyle(fontSize: 9)),
                  ),
              ],
            ),
        ],
      );
    }

    String money(double value) => '$currencySymbol ${currency.format(value)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          final content = <pw.Widget>[];

          // Header
          content.add(
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      businessName.isEmpty ? 'Reporte' : businessName,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal900,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Reporte de Estadísticas',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Rango: ${date.format(rangeStart)} - ${date.format(rangeEnd)}',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                    if (website != null && website.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.UrlLink(
                        destination: website,
                        child: pw.Text(
                          website,
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.blue,
                            decoration: pw.TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.teal,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Text(
                    'FULLPOS',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
          content.add(pw.SizedBox(height: 12));
          content.add(pw.Divider(color: PdfColors.grey400));

          // KPIs
          if (sections['kpis'] == true) {
            content.add(sectionTitle('KPIs'));
            if (kpis == null) {
              content.add(
                pw.Text(
                  'Sin datos de KPIs para el rango.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              );
            } else {
              content.add(kvRow('Total Ventas:', money(kpis.totalSales)));
              content.add(kvRow('Ganancia:', money(kpis.totalProfit)));
              content.add(kvRow('Cantidad Ventas:', '${kpis.salesCount}'));
              content.add(kvRow('Ticket Promedio:', money(kpis.avgTicket)));
              content.add(pw.SizedBox(height: 6));
            }
          }

          // Sales series
          if (sections['salesSeries'] == true) {
            content.add(sectionTitle('Ventas por Período'));
            final rows = salesSeries
                .take(40)
                .map((p) => [p.label, money(p.value)])
                .toList();
            if (rows.isEmpty) {
              content.add(
                pw.Text(
                  'Sin datos en el rango.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              );
            } else {
              content.add(
                simpleTable(headers: ['Período', 'Ventas'], rows: rows),
              );
            }
          }

          // Payment methods
          if (sections['paymentMethods'] == true) {
            content.add(sectionTitle('Métodos de Pago'));
            final rows = paymentMethods
                .map((m) => [m.method, money(m.amount), '${m.count}'])
                .toList();
            if (rows.isEmpty) {
              content.add(
                pw.Text(
                  'Sin datos en el rango.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              );
            } else {
              content.add(
                simpleTable(headers: ['Método', 'Monto', 'Cant.'], rows: rows),
              );
            }
          }

          // Profit series
          if (sections['profitSeries'] == true) {
            content.add(sectionTitle('Ganancias por Período'));
            final rows = profitSeries
                .take(40)
                .map((p) => [p.label, money(p.value)])
                .toList();
            if (rows.isEmpty) {
              content.add(
                pw.Text(
                  'Sin datos en el rango.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              );
            } else {
              content.add(
                simpleTable(headers: ['Período', 'Ganancias'], rows: rows),
              );
            }
          }

          // Comparative stats
          if (sections['comparativeStats'] == true) {
            content.add(sectionTitle('Comparativa de Ventas'));
            if (comparativeStats.isEmpty) {
              content.add(
                pw.Text(
                  'Sin datos comparativos.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              );
            } else {
              final entries = comparativeStats.entries.toList();
              entries.sort((a, b) => a.key.compareTo(b.key));
              final rows = entries
                  .take(30)
                  .map((e) => [e.key, '${e.value}'])
                  .toList();
              content.add(
                simpleTable(headers: ['Indicador', 'Valor'], rows: rows),
              );
            }
          }

          // Tabs (tables)
          if (sections['topProducts'] == true) {
            content.add(sectionTitle('Top Productos'));
            final rows = topProducts
                .take(15)
                .map(
                  (p) => [
                    p.productName,
                    money(p.totalSales),
                    p.totalQty.toStringAsFixed(0),
                    money(p.totalProfit),
                  ],
                )
                .toList();
            if (rows.isEmpty) {
              content.add(
                pw.Text('Sin datos.', style: const pw.TextStyle(fontSize: 10)),
              );
            } else {
              content.add(
                simpleTable(
                  headers: ['Producto', 'Ventas', 'Cant.', 'Ganancia'],
                  rows: rows,
                ),
              );
            }
          }

          if (sections['topClients'] == true) {
            content.add(sectionTitle('Top Clientes'));
            final rows = topClients
                .take(15)
                .map(
                  (c) => [
                    c.clientName,
                    money(c.totalSpent),
                    '${c.purchaseCount}',
                  ],
                )
                .toList();
            if (rows.isEmpty) {
              content.add(
                pw.Text('Sin datos.', style: const pw.TextStyle(fontSize: 10)),
              );
            } else {
              content.add(
                simpleTable(
                  headers: ['Cliente', 'Total', 'Compras'],
                  rows: rows,
                ),
              );
            }
          }

          if (sections['salesList'] == true) {
            content.add(sectionTitle('Ventas (Listado)'));
            final rows = salesList
                .take(50)
                .map(
                  (s) => [
                    s.localCode,
                    date.format(
                      DateTime.fromMillisecondsSinceEpoch(s.createdAtMs),
                    ),
                    (s.customerName ?? 'Cliente General'),
                    money(s.total),
                    (s.paymentMethod ?? 'N/A'),
                  ],
                )
                .toList();
            if (rows.isEmpty) {
              content.add(
                pw.Text('Sin datos.', style: const pw.TextStyle(fontSize: 10)),
              );
            } else {
              content.add(
                simpleTable(
                  headers: ['Código', 'Fecha', 'Cliente', 'Total', 'Método'],
                  rows: rows,
                ),
              );
            }
          }

          return content;
        },
        footer: (context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 12),
            child: pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }
}
