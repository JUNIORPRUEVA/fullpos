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

    const PdfColor brandBlue = PdfColor(0.11, 0.23, 0.54);
    const PdfColor brandBlueSoft = PdfColor(0.92, 0.95, 1);
    const PdfColor brandTeal = PdfColor(0.05, 0.55, 0.52);
    const PdfColor brandRose = PdfColor(0.79, 0.24, 0.31);
    const PdfColor softBorder = PdfColor(0.87, 0.90, 0.95);
    const PdfColor surfaceMuted = PdfColor(0.97, 0.98, 0.99);

    final businessName = appConfigService.getBusinessName().trim();
    final website = appConfigService.getWebsite()?.trim();
    final currencySymbol = appConfigService.getCurrencySymbol().trim();
    final currency = NumberFormat('#,##0.00', 'en_US');
    final date = DateFormat('dd/MM/yyyy');

    String money(double value) => '$currencySymbol ${currency.format(value)}';

    pw.Widget sectionTitle(String title, {String? subtitle}) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 8),
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: pw.BoxDecoration(
          color: brandBlueSoft,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: brandBlue,
              ),
            ),
            if (subtitle != null) ...[
              pw.SizedBox(height: 3),
              pw.Text(
                subtitle,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
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
        border: pw.TableBorder.all(color: softBorder, width: 0.5),
        columnWidths: {
          for (var i = 0; i < headers.length; i++)
            i: const pw.FlexColumnWidth(),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: brandBlueSoft),
            children: [
              for (final header in headers)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    header,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          for (final row in rows)
            pw.TableRow(
              children: [
                for (final cell in row)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(
                      cell,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
              ],
            ),
        ],
      );
    }

    pw.Widget summaryCard({
      required String label,
      required String value,
      required PdfColor tone,
      String? secondary,
    }) {
      return pw.Container(
        width: 160,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: surfaceMuted,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: softBorder, width: 0.7),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: tone,
              ),
            ),
            if (secondary != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                secondary,
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
        ),
      );
    }

    pw.Widget bulletRows(List<String> rows) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows
            .map(
              (row) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('• ', style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Expanded(
                      child: pw.Text(
                        row,
                        style: const pw.TextStyle(fontSize: 9.5),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    }

    Map<String, dynamic> comparativeEntry(String key) =>
        (comparativeStats[key] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    double comparativeSales(String key) =>
        (comparativeEntry(key)['sales'] as num?)?.toDouble() ?? 0.0;

    int comparativeCount(String key) =>
        (comparativeEntry(key)['count'] as num?)?.toInt() ?? 0;

    String deltaText(double current, double previous) {
      if (previous == 0) {
        return current == 0
            ? 'sin variacion'
            : 'nuevo crecimiento sin base previa';
      }
      final delta = ((current - previous) / previous) * 100;
      final sign = delta >= 0 ? '+' : '';
      return '$sign${delta.toStringAsFixed(1)}%';
    }

    List<String> comparativeHighlights() {
      if (comparativeStats.isEmpty) return const [];
      final todaySales = comparativeSales('today');
      final yesterdaySales = comparativeSales('yesterday');
      final weekSales = comparativeSales('thisWeek');
      final lastWeekSales = comparativeSales('lastWeek');
      final monthSales = comparativeSales('thisMonth');
      final lastMonthSales = comparativeSales('lastMonth');

      return [
        'Hoy: ${money(todaySales)} en ${comparativeCount('today')} ventas frente a ayer (${deltaText(todaySales, yesterdaySales)}).',
        'Semana actual: ${money(weekSales)} frente a ${money(lastWeekSales)} de la semana anterior (${deltaText(weekSales, lastWeekSales)}).',
        'Mes actual: ${money(monthSales)} frente a ${money(lastMonthSales)} del mes anterior (${deltaText(monthSales, lastMonthSales)}).',
      ];
    }

    List<List<String>> comparativeRows() {
      if (comparativeStats.isEmpty) return const [];
      const entries = [
        ('today', 'Hoy'),
        ('yesterday', 'Ayer'),
        ('thisWeek', 'Esta semana'),
        ('lastWeek', 'Semana pasada'),
        ('thisMonth', 'Este mes'),
        ('lastMonth', 'Mes pasado'),
      ];

      return entries
          .map(
            (entry) => [
              entry.$2,
              money(comparativeSales(entry.$1)),
              '${comparativeCount(entry.$1)}',
            ],
          )
          .toList();
    }

    final enabledSectionCount = sections.values
        .where((enabled) => enabled)
        .length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          final content = <pw.Widget>[];

          content.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: brandBlueSoft,
                borderRadius: pw.BorderRadius.circular(14),
                border: pw.Border.all(color: softBorder, width: 0.8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          businessName.isEmpty ? 'Reporte' : businessName,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: brandBlue,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Reporte ejecutivo de estadisticas',
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Rango: ${date.format(rangeStart)} - ${date.format(rangeEnd)}',
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Secciones activas: $enabledSectionCount',
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                        if (website != null && website.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
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
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: pw.BoxDecoration(
                      color: brandBlue,
                      borderRadius: pw.BorderRadius.circular(999),
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
            ),
          );
          content.add(pw.SizedBox(height: 12));

          if (kpis != null) {
            content.add(
              pw.Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  summaryCard(
                    label: 'Ventas netas',
                    value: money(kpis.totalSales),
                    tone: brandBlue,
                    secondary: '${kpis.salesCount} transacciones',
                  ),
                  summaryCard(
                    label: 'Ganancia neta',
                    value: money(kpis.netProfit),
                    tone: brandTeal,
                    secondary: 'Bruta ${money(kpis.totalProfit)}',
                  ),
                  summaryCard(
                    label: 'Balance de caja',
                    value: money(kpis.cashIncome - kpis.cashExpense),
                    tone: (kpis.cashIncome - kpis.cashExpense) >= 0
                        ? brandTeal
                        : brandRose,
                    secondary:
                        'Ingresos ${money(kpis.cashIncome)} | Egresos ${money(kpis.cashExpense)}',
                  ),
                ],
              ),
            );
          }

          if (sections['kpis'] == true) {
            content.add(
              sectionTitle(
                'KPIs',
                subtitle:
                    'Resumen financiero y comercial del periodo seleccionado.',
              ),
            );
            if (kpis == null) {
              content.add(
                pw.Text(
                  'Sin datos de KPIs para el rango.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              );
            } else {
              content.add(kvRow('Total Ventas:', money(kpis.totalSales)));
              content.add(kvRow('Ganancia Bruta:', money(kpis.totalProfit)));
              content.add(kvRow('Gastos del rango:', money(kpis.cashExpense)));
              content.add(kvRow('Ganancia Neta:', money(kpis.netProfit)));
              content.add(kvRow('Cantidad Ventas:', '${kpis.salesCount}'));
              content.add(kvRow('Cotizaciones:', '${kpis.quotesCount}'));
              content.add(
                kvRow(
                  'Conversion:',
                  kpis.quotesCount > 0
                      ? '${((kpis.quotesConverted / kpis.quotesCount) * 100).toStringAsFixed(0)}%'
                      : '0%',
                ),
              );
              content.add(kvRow('Ticket Promedio:', money(kpis.avgTicket)));
              content.add(pw.SizedBox(height: 6));
            }
          }

          if (sections['salesSeries'] == true) {
            content.add(
              sectionTitle(
                'Ventas por Período',
                subtitle: 'Serie cronologica consolidada de ventas del rango.',
              ),
            );
            final rows = salesSeries
                .take(40)
                .map((point) => [point.label, money(point.value)])
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

          if (sections['paymentMethods'] == true) {
            content.add(
              sectionTitle(
                'Métodos de Pago',
                subtitle:
                    'Distribucion real de cobro segun los montos almacenados.',
              ),
            );
            final rows = paymentMethods
                .map(
                  (method) => [
                    method.method,
                    money(method.amount),
                    '${method.count}',
                  ],
                )
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

          if (sections['profitSeries'] == true) {
            content.add(
              sectionTitle(
                'Ganancia Neta por Período',
                subtitle:
                    'Utilidad del periodo descontando devoluciones y egresos.',
              ),
            );
            final rows = profitSeries
                .take(40)
                .map((point) => [point.label, money(point.value)])
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
                simpleTable(headers: ['Período', 'Ganancia neta'], rows: rows),
              );
            }
          }

          if (sections['comparativeStats'] == true) {
            content.add(
              sectionTitle(
                'Comparativa de Ventas',
                subtitle: 'Comparacion contra cortes recientes del negocio.',
              ),
            );
            if (comparativeStats.isEmpty) {
              content.add(
                pw.Text(
                  'Sin datos comparativos.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              );
            } else {
              content.add(bulletRows(comparativeHighlights()));
              content.add(pw.SizedBox(height: 8));
              content.add(
                simpleTable(
                  headers: ['Corte', 'Ventas', 'Transacciones'],
                  rows: comparativeRows(),
                ),
              );
            }
          }

          if (sections['topProducts'] == true) {
            content.add(
              sectionTitle(
                'Top Productos',
                subtitle:
                    'Ranking de articulos con mayor facturacion y margen.',
              ),
            );
            final rows = topProducts
                .take(15)
                .map(
                  (product) => [
                    product.productName,
                    money(product.totalSales),
                    product.totalQty.toStringAsFixed(0),
                    money(product.totalProfit),
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
                  headers: ['Producto', 'Ventas', 'Cant.', 'Margen Bruto'],
                  rows: rows,
                ),
              );
            }
          }

          if (sections['topClients'] == true) {
            content.add(
              sectionTitle(
                'Top Clientes',
                subtitle: 'Clientes con mayor volumen de compra en el periodo.',
              ),
            );
            final rows = topClients
                .take(15)
                .map(
                  (client) => [
                    client.clientName,
                    money(client.totalSpent),
                    '${client.purchaseCount}',
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
            content.add(
              sectionTitle(
                'Ventas (Listado)',
                subtitle:
                    'Detalle abreviado de operaciones incluidas en el rango.',
              ),
            );
            final rows = salesList
                .take(50)
                .map(
                  (sale) => [
                    sale.localCode,
                    date.format(
                      DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs),
                    ),
                    sale.customerName ?? 'Cliente General',
                    money(sale.total),
                    sale.paymentMethod ?? 'N/A',
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
