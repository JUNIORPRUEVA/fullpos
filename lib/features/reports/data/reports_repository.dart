import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'report_data_service.dart';

/// Modelos para los reportes
class KpisData {
  final double totalSales;
  // Ganancia bruta del rango: ventas netas - costo neto.
  final double totalProfit;
  // Utilidad del rango: ventas netas - costo neto. No descuenta gastos de caja.
  final double netProfit;
  final double totalCost;
  final int salesCount;
  final int quotesCount;
  final int quotesConverted;
  final double avgTicket;
  // Caja
  final double cashIncome;
  final double cashExpense;

  KpisData({
    required this.totalSales,
    required this.totalProfit,
    double? netProfit,
    this.totalCost = 0,
    required this.salesCount,
    required this.quotesCount,
    required this.quotesConverted,
    required this.avgTicket,
    this.cashIncome = 0,
    this.cashExpense = 0,
  }) : netProfit = netProfit ?? totalProfit;
}

/// Datos para gráfico de distribución de ventas por método de pago
class PaymentMethodData {
  final String method;
  final double amount;
  final int count;

  PaymentMethodData({
    required this.method,
    required this.amount,
    required this.count,
  });
}

/// Datos para gráfico de categorías
class CategorySalesData {
  final String category;
  final double sales;
  final int itemsSold;

  CategorySalesData({
    required this.category,
    required this.sales,
    required this.itemsSold,
  });
}

class CategoryPerformanceData {
  final String category;
  final double sales;
  final double refunds;
  final double netSales;
  final double profit;
  final double itemsSold;
  final double itemsRefunded;

  CategoryPerformanceData({
    required this.category,
    required this.sales,
    required this.refunds,
    required this.netSales,
    required this.profit,
    required this.itemsSold,
    required this.itemsRefunded,
  });
}

class SeriesDataPoint {
  final String label; // fecha o período
  final double value;

  SeriesDataPoint(this.label, this.value);
}

class TopProduct {
  final int productId;
  final String productName;
  final double totalSales;
  final double totalQty;
  final double totalProfit;

  TopProduct({
    required this.productId,
    required this.productName,
    required this.totalSales,
    required this.totalQty,
    required this.totalProfit,
  });
}

class TopClient {
  final int clientId;
  final String clientName;
  final double totalSpent;
  final int purchaseCount;

  TopClient({
    required this.clientId,
    required this.clientName,
    required this.totalSpent,
    required this.purchaseCount,
  });
}

class ClientSalesSummary {
  final int clientId;
  final String clientName;
  final double totalSales;
  final double totalCredit;
  final int salesCount;
  final int lastPurchaseAtMs;

  ClientSalesSummary({
    required this.clientId,
    required this.clientName,
    required this.totalSales,
    required this.totalCredit,
    required this.salesCount,
    required this.lastPurchaseAtMs,
  });
}

class SalesByUser {
  final int userId;
  final String username;
  final double totalSales;
  final int salesCount;

  SalesByUser({
    required this.userId,
    required this.username,
    required this.totalSales,
    required this.salesCount,
  });
}

class SaleRecord {
  final int id;
  final int? customerId;
  final String localCode;
  final String kind;
  final int createdAtMs;
  final String? customerName;
  final double total;
  final String? paymentMethod;

  SaleRecord({
    required this.id,
    this.customerId,
    required this.localCode,
    required this.kind,
    required this.createdAtMs,
    this.customerName,
    required this.total,
    this.paymentMethod,
  });
}

/// Repositorio para generar reportes y estadísticas
class ReportsRepository {
  ReportsRepository._();

  static String _normalizePaymentMethodLabel(String? method) {
    return switch ((method ?? '').trim().toLowerCase()) {
      '' || 'cash' || 'efectivo' => 'Efectivo',
      'card' || 'tarjeta' => 'Tarjeta',
      'transfer' || 'transferencia' => 'Transferencia',
      'credit' || 'credito' => 'Crédito',
      'layaway' || 'apartado' => 'Apartado',
      'mixed' || 'mixto' => 'Mixto',
      _ => (method ?? 'Efectivo').trim(),
    };
  }

  static Map<String, double> _paymentBucketsForSale({
    required String? paymentMethod,
    required double total,
    required double paymentCashAmount,
    required double paymentCardAmount,
    required double paymentTransferAmount,
  }) {
    final buckets = <String, double>{};

    void add(String method, double amount) {
      if (amount.abs() <= 0.009) return;
      buckets[method] = (buckets[method] ?? 0.0) + amount;
    }

    final normalizedMethod = _normalizePaymentMethodLabel(paymentMethod);
    final hasBreakdown =
        paymentCashAmount.abs() > 0.009 ||
        paymentCardAmount.abs() > 0.009 ||
        paymentTransferAmount.abs() > 0.009;

    if (hasBreakdown || normalizedMethod == 'Mixto') {
      add('Efectivo', paymentCashAmount);
      add('Tarjeta', paymentCardAmount);
      add('Transferencia', paymentTransferAmount);

      final assigned =
          paymentCashAmount + paymentCardAmount + paymentTransferAmount;
      final residual = total - assigned;
      if (residual.abs() > 0.009) {
        add(normalizedMethod == 'Mixto' ? 'Mixto' : normalizedMethod, residual);
      }

      if (buckets.isNotEmpty) {
        return buckets;
      }
    }

    add(normalizedMethod, total);
    return buckets;
  }

  static Map<String, double> _paymentBucketsForReturn({
    required String? originalPaymentMethod,
    required double originalTotal,
    required double returnTotal,
    required double originalPaymentCashAmount,
    required double originalPaymentCardAmount,
    required double originalPaymentTransferAmount,
  }) {
    final buckets = <String, double>{};

    void add(String method, double amount) {
      if (amount.abs() <= 0.009) return;
      buckets[method] = (buckets[method] ?? 0.0) + amount;
    }

    final normalizedMethod = _normalizePaymentMethodLabel(
      originalPaymentMethod,
    );
    final absoluteOriginalTotal = originalTotal.abs();
    final hasBreakdown =
        originalPaymentCashAmount.abs() > 0.009 ||
        originalPaymentCardAmount.abs() > 0.009 ||
        originalPaymentTransferAmount.abs() > 0.009;

    if (hasBreakdown && absoluteOriginalTotal > 0.009) {
      add(
        'Efectivo',
        returnTotal * (originalPaymentCashAmount / absoluteOriginalTotal),
      );
      add(
        'Tarjeta',
        returnTotal * (originalPaymentCardAmount / absoluteOriginalTotal),
      );
      add(
        'Transferencia',
        returnTotal * (originalPaymentTransferAmount / absoluteOriginalTotal),
      );

      final assigned =
          originalPaymentCashAmount +
          originalPaymentCardAmount +
          originalPaymentTransferAmount;
      final residual = absoluteOriginalTotal - assigned;
      if (residual.abs() > 0.009) {
        add(
          normalizedMethod == 'Mixto' ? 'Mixto' : normalizedMethod,
          returnTotal * (residual / absoluteOriginalTotal),
        );
      }

      if (buckets.isNotEmpty) {
        return buckets;
      }
    }

    add(normalizedMethod, returnTotal);
    return buckets;
  }

  /// Obtiene KPIs para el rango de fechas
  static Future<KpisData> getKpis({
    required int startMs,
    required int endMs,
    int? userId,
  }) async {
    final db = await AppDb.database;
    final report = await ReportDataService.getReportData(
      DateFilter(
        start: DateTime.fromMillisecondsSinceEpoch(startMs),
        end: DateTime.fromMillisecondsSinceEpoch(endMs),
      ),
    );

    // Intentar completar snapshots faltantes en el rango solicitado (solo si existen productos).
    // Esto evita que la ganancia quede igual a las ventas por costos en 0.
    try {
      // 1) Completar product_id cuando venga NULL, usando el código snapshot.
      await db.execute(
        '''
        UPDATE ${DbTables.saleItems}
        SET product_id = (
          SELECT p.id FROM ${DbTables.products} p
          WHERE TRIM(p.code) COLLATE NOCASE = TRIM(${DbTables.saleItems}.product_code_snapshot) COLLATE NOCASE
          LIMIT 1
        )
        WHERE product_id IS NULL
          AND product_code_snapshot IS NOT NULL
          AND TRIM(product_code_snapshot) <> ''
          AND product_code_snapshot <> 'N/A'
          AND sale_id IN (
            SELECT id FROM ${DbTables.sales}
            WHERE kind IN ('invoice', 'sale')
              AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
              AND deleted_at_ms IS NULL
              AND created_at_ms >= ?
              AND created_at_ms <= ?
          )
          AND EXISTS (
            SELECT 1 FROM ${DbTables.products} p
            WHERE TRIM(p.code) COLLATE NOCASE = TRIM(${DbTables.saleItems}.product_code_snapshot) COLLATE NOCASE
          )
        ''',
        [startMs, endMs],
      );

      // 2) Completar purchase_price_snapshot usando el costo actual del producto.
      await db.execute(
        '''
        UPDATE ${DbTables.saleItems}
        SET purchase_price_snapshot = (
          SELECT COALESCE(p.purchase_price, 0)
          FROM ${DbTables.products} p
          WHERE p.id = ${DbTables.saleItems}.product_id
             OR TRIM(p.code) COLLATE NOCASE = TRIM(${DbTables.saleItems}.product_code_snapshot) COLLATE NOCASE
          LIMIT 1
        )
        WHERE (purchase_price_snapshot IS NULL OR purchase_price_snapshot <= 0)
          AND sale_id IN (
            SELECT id FROM ${DbTables.sales}
            WHERE kind IN ('invoice', 'sale')
              AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
              AND deleted_at_ms IS NULL
              AND created_at_ms >= ?
              AND created_at_ms <= ?
          )
          AND EXISTS (
            SELECT 1 FROM ${DbTables.products} p
            WHERE (
              p.id = ${DbTables.saleItems}.product_id
              OR TRIM(p.code) COLLATE NOCASE = TRIM(${DbTables.saleItems}.product_code_snapshot) COLLATE NOCASE
            )
              AND COALESCE(p.purchase_price, 0) > 0
          )
        ''',
        [startMs, endMs],
      );
    } catch (_) {
      // No bloquear reportes si no se puede backfillear
    }

    final netTotalSales = report.totalSales;
    final netTotalCost = report.totalCost;
    double cashIncome = 0;
    try {
      final cashIncomeQuery =
          '''
        SELECT COALESCE(SUM(amount), 0) as total
        FROM ${DbTables.cashMovements}
        WHERE type = 'IN'
          AND created_at_ms >= ?
          AND created_at_ms <= ?
      ''';
      final cashIncomeResult = await db.rawQuery(cashIncomeQuery, [
        startMs,
        endMs,
      ]);
      cashIncome = (cashIncomeResult.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      // La tabla puede no existir
    }

    final grossProfit = report.grossProfit;
    final netProfit = grossProfit;

    double finalTotalSales = netTotalSales;
    double finalTotalProfit = grossProfit;
    double finalTotalCost = netTotalCost;
    int finalSalesCount = report.sales.length;
    double finalAvgTicket = finalSalesCount > 0
        ? (netTotalSales / finalSalesCount)
        : 0.0;
    // Cotizaciones
    final quotesQuery =
        '''
      SELECT COUNT(id) as quotes_count
      FROM ${DbTables.sales}
      WHERE kind = 'quote'
        AND deleted_at_ms IS NULL
        AND created_at_ms >= ?
        AND created_at_ms <= ?
    ''';

    final quotesResult = await db.rawQuery(quotesQuery, [startMs, endMs]);
    final quotesCount = (quotesResult.first['quotes_count'] as int?) ?? 0;

    // Cotizaciones convertidas (las que tienen status='converted' o similar)
    // Nota: si no tienes este campo, cuenta las ventas que tengan referencia a quote
    final quotesConvertedQuery =
        '''
      SELECT COUNT(id) as converted_count
      FROM ${DbTables.sales}
      WHERE kind IN ('invoice', 'sale')
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
        AND deleted_at_ms IS NULL
        AND created_at_ms >= ?
        AND created_at_ms <= ?
    ''';

    final quotesConvertedResult = await db.rawQuery(quotesConvertedQuery, [
      startMs,
      endMs,
    ]);
    final quotesConverted =
        (quotesConvertedResult.first['converted_count'] as int?) ?? 0;

    return KpisData(
      totalSales: finalTotalSales,
      totalProfit: finalTotalProfit,
      netProfit: netProfit,
      totalCost: finalTotalCost,
      salesCount: finalSalesCount,
      quotesCount: quotesCount,
      quotesConverted: quotesConverted,
      avgTicket: finalAvgTicket,
      cashIncome: cashIncome,
      cashExpense: 0,
    );
  }

  /// Serie temporal de ventas totales por día
  static Future<List<SeriesDataPoint>> getSalesSeries({
    required int startMs,
    required int endMs,
    String groupBy = 'day', // day, week, month
  }) async {
    final db = await AppDb.database;

    final results = await db.rawQuery(
      '''
        SELECT 
          DATE(datetime(created_at_ms/1000, 'unixepoch', 'localtime')) as date_label,
          COALESCE(SUM(
            CASE
              WHEN kind = 'return' THEN -ABS(COALESCE(total, 0))
              ELSE COALESCE(total, 0)
            END
          ), 0) as daily_total
        FROM ${DbTables.sales}
        WHERE kind IN ('invoice', 'sale', 'return')
          AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND deleted_at_ms IS NULL
          AND created_at_ms >= ?
          AND created_at_ms <= ?
        GROUP BY date_label
        ORDER BY date_label ASC
      ''',
      [startMs, endMs],
    );

    return results.map((row) {
      final label = row['date_label'] as String;
      final value = (row['daily_total'] as num?)?.toDouble() ?? 0.0;
      return SeriesDataPoint(label, value);
    }).toList();
  }

  /// Ventas y devoluciones por categoria (neto + ganancia)
  static Future<List<CategoryPerformanceData>> getCategoryPerformance({
    required int startMs,
    required int endMs,
  }) async {
    final db = await AppDb.database;
    final rows = await db.rawQuery(
      '''
      WITH invoice_item_totals AS (
        SELECT
          si.sale_id,
          COALESCE(SUM(COALESCE(si.total_line, 0)), 0) as items_total
        FROM ${DbTables.saleItems} si
        GROUP BY si.sale_id
      ),
      return_item_totals AS (
        SELECT
          ri.return_id,
          COALESCE(SUM(COALESCE(ri.total, 0)), 0) as items_total
        FROM ${DbTables.returnItems} ri
        GROUP BY ri.return_id
      )
      SELECT
        category,
        COALESCE(SUM(sales_total), 0) as sales_total,
        COALESCE(SUM(refund_total), 0) as refund_total,
        COALESCE(SUM(items_sold), 0) as items_sold,
        COALESCE(SUM(items_refunded), 0) as items_refunded,
        COALESCE(SUM(profit_before_expenses), 0) as profit_before_expenses
      FROM (
        SELECT
          COALESCE(c.name, 'Sin categoria') as category,
          COALESCE(SUM(
            CASE
              WHEN COALESCE(it.items_total, 0) > 0
                THEN COALESCE(s.total, 0) * (COALESCE(si.total_line, 0) / it.items_total)
              ELSE 0
            END
          ), 0) as sales_total,
          0 as refund_total,
          COALESCE(SUM(si.qty), 0) as items_sold,
          0 as items_refunded,
          COALESCE(SUM(
            CASE
              WHEN COALESCE(it.items_total, 0) > 0
                THEN COALESCE(s.total, 0) * (COALESCE(si.total_line, 0) / it.items_total)
              ELSE 0
            END
            - (COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))
          ), 0) as profit_before_expenses
        FROM ${DbTables.saleItems} si
        INNER JOIN ${DbTables.sales} s ON si.sale_id = s.id
        LEFT JOIN invoice_item_totals it ON it.sale_id = si.sale_id
        LEFT JOIN ${DbTables.products} p
          ON (si.product_id = p.id)
          OR (
            si.product_id IS NULL
            AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
          )
        LEFT JOIN ${DbTables.categories} c ON p.category_id = c.id
        WHERE s.kind IN ('invoice', 'sale')
          AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND s.deleted_at_ms IS NULL
          AND s.created_at_ms >= ?
          AND s.created_at_ms <= ?
        GROUP BY category
        UNION ALL
        SELECT
          COALESCE(c.name, 'Sin categoria') as category,
          0 as sales_total,
          COALESCE(SUM(
            CASE
              WHEN COALESCE(rt.items_total, 0) > 0
                THEN ABS(COALESCE(s.total, 0)) * (COALESCE(ri.total, 0) / rt.items_total)
              ELSE 0
            END
          ), 0) as refund_total,
          0 as items_sold,
          COALESCE(SUM(ri.qty), 0) as items_refunded,
          COALESCE(SUM(
            (COALESCE(ri.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))
            - CASE
              WHEN COALESCE(rt.items_total, 0) > 0
                THEN ABS(COALESCE(s.total, 0)) * (COALESCE(ri.total, 0) / rt.items_total)
              ELSE 0
            END
          ), 0) as profit_before_expenses
        FROM ${DbTables.returnItems} ri
        INNER JOIN ${DbTables.returns} r ON ri.return_id = r.id
        INNER JOIN ${DbTables.sales} s ON r.return_sale_id = s.id
        LEFT JOIN return_item_totals rt ON rt.return_id = ri.return_id
        LEFT JOIN ${DbTables.saleItems} si ON ri.sale_item_id = si.id
        LEFT JOIN ${DbTables.products} p ON COALESCE(ri.product_id, si.product_id) = p.id
        LEFT JOIN ${DbTables.categories} c ON p.category_id = c.id
        WHERE s.kind = 'return'
          AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND s.deleted_at_ms IS NULL
          AND s.created_at_ms >= ?
          AND s.created_at_ms <= ?
        GROUP BY category
      ) t
      GROUP BY category
      ORDER BY sales_total DESC, refund_total DESC
      ''',
      [startMs, endMs, startMs, endMs],
    );

    return rows.map((row) {
      final sales = (row['sales_total'] as num?)?.toDouble() ?? 0.0;
      final refunds = (row['refund_total'] as num?)?.toDouble() ?? 0.0;
      final netSales = sales - refunds;
      final profitBeforeExpenses =
          (row['profit_before_expenses'] as num?)?.toDouble() ?? 0.0;
      return CategoryPerformanceData(
        category: row['category'] as String? ?? 'Sin categoria',
        sales: sales,
        refunds: refunds,
        netSales: netSales,
        profit: profitBeforeExpenses,
        itemsSold: (row['items_sold'] as num?)?.toDouble() ?? 0.0,
        itemsRefunded: (row['items_refunded'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }

  /// Serie temporal de utilidad por día
  static Future<List<SeriesDataPoint>> getProfitSeries({
    required int startMs,
    required int endMs,
  }) async {
    final db = await AppDb.database;

    final results = await db.rawQuery(
      '''
        SELECT date_label, COALESCE(SUM(daily_profit), 0) as daily_profit
        FROM (
          SELECT 
            DATE(datetime(s.created_at_ms/1000, 'unixepoch', 'localtime')) as date_label,
            COALESCE(SUM(COALESCE(s.total, 0)), 0) as daily_profit
          FROM ${DbTables.sales} s
          WHERE s.kind IN ('invoice', 'sale')
            AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
            AND s.deleted_at_ms IS NULL
            AND s.created_at_ms >= ?
            AND s.created_at_ms <= ?
          GROUP BY date_label
          UNION ALL
          SELECT
            DATE(datetime(s.created_at_ms/1000, 'unixepoch', 'localtime')) as date_label,
            -COALESCE(SUM(ABS(s.total)), 0) as daily_profit
          FROM ${DbTables.sales} s
          WHERE s.kind = 'return'
            AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
            AND s.deleted_at_ms IS NULL
            AND s.created_at_ms >= ?
            AND s.created_at_ms <= ?
          GROUP BY date_label
          UNION ALL
          SELECT 
            DATE(datetime(s.created_at_ms/1000, 'unixepoch', 'localtime')) as date_label,
            -COALESCE(SUM(
              COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)
            ), 0) as daily_profit
          FROM ${DbTables.saleItems} si
          INNER JOIN ${DbTables.sales} s ON si.sale_id = s.id
          LEFT JOIN ${DbTables.products} p
            ON (si.product_id = p.id)
            OR (
              si.product_id IS NULL
              AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
            )
          WHERE s.kind IN ('invoice', 'sale')
            AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
            AND s.deleted_at_ms IS NULL
            AND s.created_at_ms >= ?
            AND s.created_at_ms <= ?
          GROUP BY date_label
          UNION ALL
          SELECT
            DATE(datetime(s.created_at_ms/1000, 'unixepoch', 'localtime')) as date_label,
            COALESCE(SUM(
              ri.qty * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)
            ), 0) as daily_profit
          FROM ${DbTables.returnItems} ri
          INNER JOIN ${DbTables.returns} r ON ri.return_id = r.id
          INNER JOIN ${DbTables.sales} s ON r.return_sale_id = s.id
          LEFT JOIN ${DbTables.saleItems} si ON ri.sale_item_id = si.id
          LEFT JOIN ${DbTables.products} p ON COALESCE(ri.product_id, si.product_id) = p.id
          WHERE s.kind = 'return'
            AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
            AND s.deleted_at_ms IS NULL
            AND s.created_at_ms >= ?
            AND s.created_at_ms <= ?
          GROUP BY date_label
        ) t
        GROUP BY date_label
        ORDER BY date_label ASC
      ''',
      [startMs, endMs, startMs, endMs, startMs, endMs, startMs, endMs],
    );

    var series = results.map((row) {
      final label = row['date_label'] as String;
      final value = (row['daily_profit'] as num?)?.toDouble() ?? 0.0;
      return SeriesDataPoint(label, value);
    }).toList();

    if (series.isEmpty) {
      final fallback = await db.rawQuery(
        '''
          SELECT 
            DATE(datetime(created_at_ms/1000, 'unixepoch', 'localtime')) as date_label
          FROM ${DbTables.sales}
          WHERE kind IN ('invoice', 'sale', 'return')
            AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
            AND deleted_at_ms IS NULL
            AND created_at_ms >= ?
            AND created_at_ms <= ?
          GROUP BY date_label
          ORDER BY date_label ASC
        ''',
        [startMs, endMs],
      );

      series = fallback.map((row) {
        final label = row['date_label'] as String;
        return SeriesDataPoint(label, 0.0);
      }).toList();
    }

    return series;
  }

  /// Top productos por ventas
  static Future<List<TopProduct>> getTopProducts({
    required int startMs,
    required int endMs,
    int limit = 10,
  }) async {
    final db = await AppDb.database;

    final query =
        '''
      WITH sale_item_totals AS (
        SELECT
          si.sale_id,
          COALESCE(SUM(COALESCE(si.total_line, 0)), 0) as items_total
        FROM ${DbTables.saleItems} si
        GROUP BY si.sale_id
      ),
      return_item_totals AS (
        SELECT
          ri.return_id,
          COALESCE(SUM(COALESCE(ri.total, 0)), 0) as items_total
        FROM ${DbTables.returnItems} ri
        GROUP BY ri.return_id
      )
      SELECT
        product_id,
        COALESCE(
          NULLIF(TRIM(master_name), ''),
          NULLIF(TRIM(MAX(snapshot_name)), ''),
          'Producto sin nombre'
        ) as product_name,
        COALESCE(SUM(total_sales), 0) as total_sales,
        COALESCE(SUM(total_qty), 0) as total_qty,
        COALESCE(SUM(profit_before_expenses), 0) as profit_before_expenses
      FROM (
        SELECT 
          COALESCE(si.product_id, p.id) as product_id,
          (CASE WHEN LENGTH(TRIM(COALESCE(si.product_name_snapshot, ''))) > 0 THEN si.product_name_snapshot ELSE COALESCE(p.name, '') END) as snapshot_name,
          COALESCE(p.name, '') as master_name,
          COALESCE(
            CASE
              WHEN COALESCE(st.items_total, 0) > 0
                THEN COALESCE(s.total, 0) * (COALESCE(si.total_line, 0) / st.items_total)
              ELSE 0
            END,
            0
          ) as total_sales,
          COALESCE(si.qty, 0) as total_qty,
          COALESCE(
            CASE
              WHEN COALESCE(st.items_total, 0) > 0
                THEN COALESCE(s.total, 0) * (COALESCE(si.total_line, 0) / st.items_total)
              ELSE 0
            END,
            0
          ) - (COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)) as profit_before_expenses
        FROM ${DbTables.saleItems} si
        INNER JOIN ${DbTables.sales} s ON si.sale_id = s.id
        LEFT JOIN sale_item_totals st ON st.sale_id = si.sale_id
        LEFT JOIN ${DbTables.products} p
          ON (si.product_id = p.id)
          OR (
            si.product_id IS NULL
            AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
          )
        WHERE s.kind IN ('invoice', 'sale')
          AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND s.deleted_at_ms IS NULL
          AND s.created_at_ms >= ?
          AND s.created_at_ms <= ?
        UNION ALL
        SELECT
          COALESCE(ri.product_id, si.product_id, p.id) as product_id,
          (CASE
            WHEN si.product_name_snapshot IS NOT NULL AND LENGTH(TRIM(si.product_name_snapshot)) > 0 THEN si.product_name_snapshot
            WHEN p.name IS NOT NULL AND LENGTH(TRIM(p.name)) > 0 THEN p.name
            ELSE COALESCE(ri.description, '')
          END) as snapshot_name,
          COALESCE(p.name, '') as master_name,
          -COALESCE(
            CASE
              WHEN COALESCE(rt.items_total, 0) > 0
                THEN ABS(COALESCE(s.total, 0)) * (COALESCE(ri.total, 0) / rt.items_total)
              ELSE 0
            END,
            0
          ) as total_sales,
          -COALESCE(ri.qty, 0) as total_qty,
          (
            COALESCE(ri.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)
          ) - COALESCE(
            CASE
              WHEN COALESCE(rt.items_total, 0) > 0
                THEN ABS(COALESCE(s.total, 0)) * (COALESCE(ri.total, 0) / rt.items_total)
              ELSE 0
            END,
            0
          ) as profit_before_expenses
        FROM ${DbTables.returnItems} ri
        INNER JOIN ${DbTables.returns} r ON ri.return_id = r.id
        INNER JOIN ${DbTables.sales} s ON r.return_sale_id = s.id
        LEFT JOIN return_item_totals rt ON rt.return_id = ri.return_id
        LEFT JOIN ${DbTables.saleItems} si ON ri.sale_item_id = si.id
        LEFT JOIN ${DbTables.products} p ON COALESCE(ri.product_id, si.product_id) = p.id
        WHERE s.kind = 'return'
          AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND s.deleted_at_ms IS NULL
          AND s.created_at_ms >= ?
          AND s.created_at_ms <= ?
      ) t
      GROUP BY
        product_id,
        master_name,
        CASE WHEN product_id IS NULL THEN snapshot_name ELSE NULL END
      ORDER BY total_sales DESC
      LIMIT ?
    ''';

    final results = await db.rawQuery(query, [
      startMs,
      endMs,
      startMs,
      endMs,
      limit,
    ]);

    return results.map((row) {
      final totalSales = (row['total_sales'] as num?)?.toDouble() ?? 0.0;
      final profitBeforeExpenses =
          (row['profit_before_expenses'] as num?)?.toDouble() ?? 0.0;
      return TopProduct(
        productId: row['product_id'] as int? ?? 0,
        productName: row['product_name'] as String? ?? '',
        totalSales: totalSales,
        totalQty: (row['total_qty'] as num?)?.toDouble() ?? 0.0,
        totalProfit: profitBeforeExpenses,
      );
    }).toList();
  }

  /// Top clientes por monto gastado
  static Future<List<TopClient>> getTopClients({
    required int startMs,
    required int endMs,
    int limit = 10,
  }) async {
    final db = await AppDb.database;

    final query =
        '''
      SELECT
        t.client_id,
        COALESCE(
          NULLIF(TRIM(c.nombre), ''),
          NULLIF(TRIM(t.snapshot_name), ''),
          'Cliente General'
        ) AS client_name,
        t.total_spent,
        t.purchase_count
      FROM (
        SELECT
          s.customer_id AS client_id,
          MAX(COALESCE(s.customer_name_snapshot, '')) AS snapshot_name,
          COALESCE(SUM(
            CASE
              WHEN s.kind = 'return' THEN -ABS(COALESCE(s.total, 0))
              ELSE COALESCE(s.total, 0)
            END
          ), 0) AS total_spent,
          COALESCE(SUM(CASE WHEN s.kind IN ('invoice', 'sale') THEN 1 ELSE 0 END), 0) AS purchase_count
        FROM ${DbTables.sales} s
        WHERE s.kind IN ('invoice', 'sale', 'return')
          AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND s.deleted_at_ms IS NULL
          AND s.customer_id IS NOT NULL
          AND s.created_at_ms >= ?
          AND s.created_at_ms <= ?
        GROUP BY s.customer_id
      ) t
      LEFT JOIN ${DbTables.clients} c ON c.id = t.client_id
      ORDER BY total_spent DESC
      LIMIT ?
    ''';

    final results = await db.rawQuery(query, [startMs, endMs, limit]);

    return results.map((row) {
      return TopClient(
        clientId: row['client_id'] as int? ?? 0,
        clientName: row['client_name'] as String? ?? 'Cliente General',
        totalSpent: (row['total_spent'] as num?)?.toDouble() ?? 0.0,
        purchaseCount: row['purchase_count'] as int? ?? 0,
      );
    }).toList();
  }

  /// Ventas por usuario
  static Future<List<SalesByUser>> getSalesByUser({
    required int startMs,
    required int endMs,
  }) async {
    final db = await AppDb.database;

    // Nota: si no tienes user_id en sales, ajusta según tu esquema
    final query =
        '''
      SELECT 
        1 as user_id,
        'admin' as username,
        COALESCE(SUM(
          CASE
            WHEN s.kind = 'return' THEN -ABS(COALESCE(s.total, 0))
            ELSE COALESCE(s.total, 0)
          END
        ), 0) as total_sales,
        COALESCE(SUM(CASE WHEN s.kind IN ('invoice', 'sale') THEN 1 ELSE 0 END), 0) as sales_count
      FROM ${DbTables.sales} s
      WHERE s.kind IN ('invoice', 'sale', 'return')
        AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
        AND s.deleted_at_ms IS NULL
        AND s.created_at_ms >= ?
        AND s.created_at_ms <= ?
    ''';

    final results = await db.rawQuery(query, [startMs, endMs]);

    return results.map((row) {
      return SalesByUser(
        userId: row['user_id'] as int? ?? 1,
        username: row['username'] as String? ?? 'admin',
        totalSales: (row['total_sales'] as num?)?.toDouble() ?? 0.0,
        salesCount: row['sales_count'] as int? ?? 0,
      );
    }).toList();
  }

  /// Lista de ventas para el rango
  static Future<List<SaleRecord>> getSalesList({
    required int startMs,
    required int endMs,
    int? userId,
  }) async {
    final report = await ReportDataService.getReportData(
      DateFilter(
        start: DateTime.fromMillisecondsSinceEpoch(startMs),
        end: DateTime.fromMillisecondsSinceEpoch(endMs),
      ),
    );

    return report.sales
        .map(
          (sale) => SaleRecord(
            id: sale.id ?? 0,
            customerId: sale.customerId,
            localCode: sale.localCode,
            kind: sale.kind,
            createdAtMs: sale.createdAtMs,
            customerName: sale.customerNameSnapshot,
            total: sale.total,
            paymentMethod: sale.paymentMethod,
          ),
        )
        .toList();
  }

  static Future<List<ClientSalesSummary>> getClientSalesSummaries({
    required int startMs,
    required int endMs,
    int limit = 200,
  }) async {
    final db = await AppDb.database;

    final query =
        '''
      SELECT
        t.client_id,
        COALESCE(
          NULLIF(TRIM(c.nombre), ''),
          NULLIF(TRIM(t.snapshot_name), ''),
          'Cliente General'
        ) AS client_name,
        COALESCE(SUM(t.total_sales), 0) AS total_sales,
        COALESCE(SUM(t.total_credit), 0) AS total_credit,
        COALESCE(SUM(t.sales_count), 0) AS sales_count,
        COALESCE(MAX(t.last_purchase_at_ms), 0) AS last_purchase_at_ms
      FROM (
        SELECT
          s.customer_id AS client_id,
          MAX(COALESCE(s.customer_name_snapshot, '')) AS snapshot_name,
          COALESCE(SUM(s.total), 0) AS total_sales,
          COALESCE(SUM(CASE WHEN COALESCE(LOWER(s.payment_method), '') = 'credit' THEN s.total ELSE 0 END), 0) AS total_credit,
          COALESCE(SUM(CASE WHEN s.kind IN ('invoice', 'sale') THEN 1 ELSE 0 END), 0) AS sales_count,
          COALESCE(MAX(s.created_at_ms), 0) AS last_purchase_at_ms
        FROM ${DbTables.sales} s
        WHERE s.kind IN ('invoice', 'sale')
          AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND s.deleted_at_ms IS NULL
          AND s.customer_id IS NOT NULL
          AND s.created_at_ms >= ?
          AND s.created_at_ms <= ?
        GROUP BY s.customer_id

        UNION ALL

        SELECT
          rs.customer_id AS client_id,
          MAX(COALESCE(rs.customer_name_snapshot, '')) AS snapshot_name,
          COALESCE(SUM(-ABS(COALESCE(rs.total, 0))), 0) AS total_sales,
          COALESCE(SUM(CASE WHEN COALESCE(LOWER(os.payment_method), '') = 'credit' THEN -ABS(COALESCE(rs.total, 0)) ELSE 0 END), 0) AS total_credit,
          0 AS sales_count,
          COALESCE(MAX(rs.created_at_ms), 0) AS last_purchase_at_ms
        FROM ${DbTables.returns} r
        INNER JOIN ${DbTables.sales} rs ON r.return_sale_id = rs.id
        INNER JOIN ${DbTables.sales} os ON r.original_sale_id = os.id
        WHERE rs.kind = 'return'
          AND rs.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND rs.deleted_at_ms IS NULL
          AND rs.customer_id IS NOT NULL
          AND rs.created_at_ms >= ?
          AND rs.created_at_ms <= ?
        GROUP BY rs.customer_id
      ) t
      LEFT JOIN ${DbTables.clients} c ON c.id = t.client_id
      GROUP BY t.client_id, c.nombre
      ORDER BY total_sales DESC
      LIMIT ?
    ''';

    final rows = await db.rawQuery(query, [
      startMs,
      endMs,
      startMs,
      endMs,
      limit,
    ]);
    return rows
        .map(
          (row) => ClientSalesSummary(
            clientId: row['client_id'] as int? ?? 0,
            clientName: row['client_name'] as String? ?? 'Cliente General',
            totalSales: (row['total_sales'] as num?)?.toDouble() ?? 0,
            totalCredit: (row['total_credit'] as num?)?.toDouble() ?? 0,
            salesCount: row['sales_count'] as int? ?? 0,
            lastPurchaseAtMs: row['last_purchase_at_ms'] as int? ?? 0,
          ),
        )
        .toList();
  }

  static Future<List<SaleRecord>> getSalesListByClient({
    required int clientId,
    required int startMs,
    required int endMs,
    int limit = 100,
  }) async {
    final db = await AppDb.database;

    final query =
        '''
      SELECT
        id,
        customer_id,
        local_code,
        kind,
        created_at_ms,
        customer_name_snapshot,
        total,
        payment_method
      FROM ${DbTables.sales}
      WHERE kind IN ('invoice', 'sale', 'return')
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
        AND deleted_at_ms IS NULL
        AND customer_id = ?
        AND created_at_ms >= ?
        AND created_at_ms <= ?
      ORDER BY created_at_ms DESC
      LIMIT ?
    ''';

    final rows = await db.rawQuery(query, [clientId, startMs, endMs, limit]);
    return rows
        .map(
          (row) => SaleRecord(
            id: row['id'] as int,
            customerId: row['customer_id'] as int?,
            localCode: row['local_code'] as String,
            kind: row['kind'] as String,
            createdAtMs: row['created_at_ms'] as int,
            customerName: row['customer_name_snapshot'] as String?,
            total: ((row['kind'] as String?) == 'return')
                ? -((row['total'] as num?)?.toDouble().abs() ?? 0)
                : ((row['total'] as num?)?.toDouble() ?? 0),
            paymentMethod: row['payment_method'] as String?,
          ),
        )
        .toList();
  }

  /// Exportar a CSV (simple)
  static Future<String> exportToCSV({
    required int startMs,
    required int endMs,
  }) async {
    final sales = await getSalesList(startMs: startMs, endMs: endMs);

    final buffer = StringBuffer();
    buffer.writeln('Código,Tipo,Fecha,Cliente,Total,Método Pago');

    for (final sale in sales) {
      final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      buffer.writeln(
        '${sale.localCode},${sale.kind},$dateStr,${sale.customerName ?? 'N/A'},${sale.total.toStringAsFixed(2)},${sale.paymentMethod ?? 'N/A'}',
      );
    }

    return buffer.toString();
  }

  /// Obtiene distribución de ventas por método de pago
  static Future<List<PaymentMethodData>> getPaymentMethodDistribution({
    required int startMs,
    required int endMs,
  }) async {
    final db = await AppDb.database;

    final salesRows = await db.rawQuery(
      '''
        SELECT
          payment_method,
          total,
          payment_cash_amount,
          payment_card_amount,
          payment_transfer_amount
        FROM ${DbTables.sales}
        WHERE kind IN ('invoice', 'sale')
          AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND deleted_at_ms IS NULL
          AND created_at_ms >= ?
          AND created_at_ms <= ?
      ''',
      [startMs, endMs],
    );

    final returnRows = await db.rawQuery(
      '''
        SELECT
          rs.total as return_total,
          os.total as original_total,
          os.payment_method as original_payment_method,
          os.payment_cash_amount as original_payment_cash_amount,
          os.payment_card_amount as original_payment_card_amount,
          os.payment_transfer_amount as original_payment_transfer_amount
        FROM ${DbTables.returns} r
        INNER JOIN ${DbTables.sales} rs ON r.return_sale_id = rs.id
        INNER JOIN ${DbTables.sales} os ON r.original_sale_id = os.id
        WHERE rs.kind = 'return'
          AND rs.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND rs.deleted_at_ms IS NULL
          AND rs.created_at_ms >= ?
          AND rs.created_at_ms <= ?
      ''',
      [startMs, endMs],
    );

    final amountsByMethod = <String, double>{};
    final countsByMethod = <String, int>{};

    void addBuckets(Map<String, double> buckets, {required bool countSales}) {
      for (final entry in buckets.entries) {
        if (entry.value.abs() <= 0.009) continue;
        amountsByMethod[entry.key] =
            (amountsByMethod[entry.key] ?? 0.0) + entry.value;
        if (countSales) {
          countsByMethod[entry.key] = (countsByMethod[entry.key] ?? 0) + 1;
        }
      }
    }

    for (final row in salesRows) {
      addBuckets(
        _paymentBucketsForSale(
          paymentMethod: row['payment_method'] as String?,
          total: (row['total'] as num?)?.toDouble() ?? 0.0,
          paymentCashAmount:
              (row['payment_cash_amount'] as num?)?.toDouble() ?? 0.0,
          paymentCardAmount:
              (row['payment_card_amount'] as num?)?.toDouble() ?? 0.0,
          paymentTransferAmount:
              (row['payment_transfer_amount'] as num?)?.toDouble() ?? 0.0,
        ),
        countSales: true,
      );
    }

    for (final row in returnRows) {
      addBuckets(
        _paymentBucketsForReturn(
          originalPaymentMethod: row['original_payment_method'] as String?,
          originalTotal: (row['original_total'] as num?)?.toDouble() ?? 0.0,
          returnTotal: (row['return_total'] as num?)?.toDouble() ?? 0.0,
          originalPaymentCashAmount:
              (row['original_payment_cash_amount'] as num?)?.toDouble() ?? 0.0,
          originalPaymentCardAmount:
              (row['original_payment_card_amount'] as num?)?.toDouble() ?? 0.0,
          originalPaymentTransferAmount:
              (row['original_payment_transfer_amount'] as num?)?.toDouble() ??
              0.0,
        ),
        countSales: false,
      );
    }

    final data =
        amountsByMethod.entries
            .map(
              (entry) => PaymentMethodData(
                method: entry.key,
                amount: entry.value,
                count: countsByMethod[entry.key] ?? 0,
              ),
            )
            .where((entry) => entry.amount > 0.009)
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    return data;
  }

  /// Obtiene estadísticas comparativas (hoy vs ayer, esta semana vs anterior)
  static Future<Map<String, dynamic>> getComparativeStats() async {
    final db = await AppDb.database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = weekStart.subtract(const Duration(milliseconds: 1));
    final monthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = monthStart.subtract(const Duration(milliseconds: 1));

    // Ventas de hoy
    final todayQuery =
        '''
      SELECT
        COALESCE(SUM(
          CASE
            WHEN kind = 'return' THEN -ABS(COALESCE(total, 0))
            ELSE COALESCE(total, 0)
          END
        ), 0) as total,
        COALESCE(SUM(CASE WHEN kind IN ('invoice', 'sale') THEN 1 ELSE 0 END), 0) as count
      FROM ${DbTables.sales}
      WHERE kind IN ('invoice', 'sale', 'return')
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
        AND deleted_at_ms IS NULL
        AND created_at_ms >= ? AND created_at_ms < ?
    ''';
    final todayResult = await db.rawQuery(todayQuery, [
      today.millisecondsSinceEpoch,
      today.add(const Duration(days: 1)).millisecondsSinceEpoch,
    ]);

    // Ventas de ayer
    final yesterdayResult = await db.rawQuery(todayQuery, [
      yesterday.millisecondsSinceEpoch,
      today.millisecondsSinceEpoch,
    ]);

    // Ventas esta semana
    final weekResult = await db.rawQuery(todayQuery, [
      weekStart.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    ]);

    // Ventas semana pasada
    final lastWeekResult = await db.rawQuery(todayQuery, [
      lastWeekStart.millisecondsSinceEpoch,
      lastWeekEnd.millisecondsSinceEpoch,
    ]);

    // Ventas este mes
    final monthResult = await db.rawQuery(todayQuery, [
      monthStart.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    ]);

    // Ventas mes pasado
    final lastMonthResult = await db.rawQuery(todayQuery, [
      lastMonthStart.millisecondsSinceEpoch,
      lastMonthEnd.millisecondsSinceEpoch,
    ]);

    return {
      'today': {
        'sales': (todayResult.first['total'] as num?)?.toDouble() ?? 0.0,
        'count': (todayResult.first['count'] as int?) ?? 0,
      },
      'yesterday': {
        'sales': (yesterdayResult.first['total'] as num?)?.toDouble() ?? 0.0,
        'count': (yesterdayResult.first['count'] as int?) ?? 0,
      },
      'thisWeek': {
        'sales': (weekResult.first['total'] as num?)?.toDouble() ?? 0.0,
        'count': (weekResult.first['count'] as int?) ?? 0,
      },
      'lastWeek': {
        'sales': (lastWeekResult.first['total'] as num?)?.toDouble() ?? 0.0,
        'count': (lastWeekResult.first['count'] as int?) ?? 0,
      },
      'thisMonth': {
        'sales': (monthResult.first['total'] as num?)?.toDouble() ?? 0.0,
        'count': (monthResult.first['count'] as int?) ?? 0,
      },
      'lastMonth': {
        'sales': (lastMonthResult.first['total'] as num?)?.toDouble() ?? 0.0,
        'count': (lastMonthResult.first['count'] as int?) ?? 0,
      },
    };
  }
}
