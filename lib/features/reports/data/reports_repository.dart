import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';

/// Modelos para los reportes
class KpisData {
  final double totalSales;
  final double totalProfit;
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
    this.totalCost = 0,
    required this.salesCount,
    required this.quotesCount,
    required this.quotesConverted,
    required this.avgTicket,
    this.cashIncome = 0,
    this.cashExpense = 0,
  });
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

  /// Obtiene KPIs para el rango de fechas
  static Future<KpisData> getKpis({
    required int startMs,
    required int endMs,
    int? userId,
  }) async {
    final db = await AppDb.database;

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

    // Totales consolidados desde sale_items.
    // Importante: usar total_line (ya calculado al guardar) para soportar datos legados
    // donde unit_price/discount pudieron quedar en 0 o inconsistentes.
    final totalsQuery =
        '''
      SELECT
        total_sales,
        total_cost,
        total_profit,
        sales_count,
        CASE WHEN sales_count > 0 THEN (total_sales / sales_count) ELSE 0 END AS avg_ticket
      FROM (
        SELECT 
          COALESCE(SUM(COALESCE(si.total_line, 0)), 0) AS total_sales,
          COALESCE(SUM(COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)), 0) AS total_cost,
          COALESCE(SUM(COALESCE(si.total_line, 0) - (COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))), 0) AS total_profit,
          COUNT(DISTINCT s.id) AS sales_count
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
      ) t
    ''';

    final totalsResult = await db.rawQuery(totalsQuery, [startMs, endMs]);
    final totalSales =
        (totalsResult.first['total_sales'] as num?)?.toDouble() ?? 0.0;
    final totalCost =
        (totalsResult.first['total_cost'] as num?)?.toDouble() ?? 0.0;
    final totalProfit =
        (totalsResult.first['total_profit'] as num?)?.toDouble() ?? 0.0;
    final salesCount = (totalsResult.first['sales_count'] as int?) ?? 0;
    final avgTicket =
        (totalsResult.first['avg_ticket'] as num?)?.toDouble() ?? 0.0;

    final returnTotalsResult = await db.rawQuery(
      '''
        SELECT
          COALESCE(SUM(ri.total), 0) as return_total,
          COALESCE(SUM(
            ri.qty * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)
          ), 0) as return_cost
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
      ''',
      [startMs, endMs],
    );

    final returnTotal =
        (returnTotalsResult.first['return_total'] as num?)?.toDouble() ?? 0.0;
    final returnCost =
        (returnTotalsResult.first['return_cost'] as num?)?.toDouble() ?? 0.0;

    final netTotalSales = totalSales - returnTotal;
    final netTotalCost = totalCost - returnCost;
    final netTotalProfit = totalProfit - (returnTotal - returnCost);

    double finalTotalSales = netTotalSales;
    double finalTotalProfit = netTotalProfit;
    double finalTotalCost = netTotalCost;
    int finalSalesCount = salesCount;
    double finalAvgTicket =
        salesCount > 0 ? (netTotalSales / salesCount) : avgTicket;

    // Fallback: si no hay items (datos legados), usar tabla sales con devoluciones incluidas.
    if (salesCount == 0 && totalSales == 0) {
      final salesOnly = await db.rawQuery(
        '''
          SELECT 
            COALESCE(SUM(CASE WHEN kind IN ('invoice','sale') THEN total ELSE 0 END), 0) AS sales_total,
            COALESCE(SUM(CASE WHEN kind = 'return' THEN total ELSE 0 END), 0) AS returns_total,
            COALESCE(SUM(CASE WHEN kind IN ('invoice','sale') THEN 1 ELSE 0 END), 0) AS sales_count
          FROM ${DbTables.sales}
          WHERE kind IN ('invoice', 'sale', 'return')
            AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
            AND deleted_at_ms IS NULL
            AND created_at_ms >= ?
            AND created_at_ms <= ?
        ''',
        [startMs, endMs],
      );

      final fallbackSales =
          (salesOnly.first['sales_total'] as num?)?.toDouble() ?? 0.0;
      final fallbackReturns =
          (salesOnly.first['returns_total'] as num?)?.toDouble() ?? 0.0;
      final fallbackSalesCount = (salesOnly.first['sales_count'] as int?) ?? 0;

      finalTotalSales = fallbackSales + fallbackReturns;
      finalSalesCount = fallbackSalesCount;
      finalAvgTicket =
          fallbackSalesCount > 0 ? (finalTotalSales / fallbackSalesCount) : 0.0;
      // Sin sale_items no se puede calcular costo/ganancia real.
      finalTotalProfit = 0.0;
      finalTotalCost = 0.0;
    }
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

    // ========== DATOS DE CAJA ==========
    double cashIncome = 0;
    double cashExpense = 0;
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

      final cashExpenseQuery =
          '''
        SELECT COALESCE(SUM(amount), 0) as total
        FROM ${DbTables.cashMovements}
        WHERE type = 'OUT'
          AND created_at_ms >= ?
          AND created_at_ms <= ?
      ''';
      final cashExpenseResult = await db.rawQuery(cashExpenseQuery, [
        startMs,
        endMs,
      ]);
      cashExpense =
          (cashExpenseResult.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {
      // La tabla puede no existir
    }

    return KpisData(
      totalSales: finalTotalSales,
      totalProfit: finalTotalProfit,
      totalCost: finalTotalCost,
      salesCount: finalSalesCount,
      quotesCount: quotesCount,
      quotesConverted: quotesConverted,
      avgTicket: finalAvgTicket,
      cashIncome: cashIncome,
      cashExpense: cashExpense,
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
          COALESCE(SUM(total), 0) as daily_total
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
      SELECT
        category,
        COALESCE(SUM(sales_total), 0) as sales_total,
        COALESCE(SUM(refund_total), 0) as refund_total,
        COALESCE(SUM(items_sold), 0) as items_sold,
        COALESCE(SUM(items_refunded), 0) as items_refunded,
        COALESCE(SUM(profit_total), 0) as profit_total
      FROM (
        SELECT
          COALESCE(c.name, 'Sin categoria') as category,
          COALESCE(SUM(si.total_line), 0) as sales_total,
          0 as refund_total,
          COALESCE(SUM(si.qty), 0) as items_sold,
          0 as items_refunded,
          COALESCE(SUM(
            COALESCE(si.total_line, 0)
            - (COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))
          ), 0) as profit_total
        FROM ${DbTables.saleItems} si
        INNER JOIN ${DbTables.sales} s ON si.sale_id = s.id
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
          COALESCE(SUM(ri.total), 0) as refund_total,
          0 as items_sold,
          COALESCE(SUM(ri.qty), 0) as items_refunded,
          COALESCE(SUM(
            (COALESCE(ri.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))
            - COALESCE(ri.total, 0)
          ), 0) as profit_total
        FROM ${DbTables.returnItems} ri
        INNER JOIN ${DbTables.returns} r ON ri.return_id = r.id
        INNER JOIN ${DbTables.sales} s ON r.return_sale_id = s.id
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
      final profit = (row['profit_total'] as num?)?.toDouble() ?? 0.0;
      return CategoryPerformanceData(
        category: row['category'] as String? ?? 'Sin categoria',
        sales: sales,
        refunds: refunds,
        netSales: netSales,
        profit: profit,
        itemsSold: (row['items_sold'] as num?)?.toDouble() ?? 0.0,
        itemsRefunded: (row['items_refunded'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }
/// Serie temporal de ganancias por día
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
            COALESCE(SUM(
              COALESCE(si.total_line, 0)
              - (COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))
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
              (ri.qty * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))
              - COALESCE(ri.total, 0)
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
      [startMs, endMs, startMs, endMs],
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
      SELECT
        product_id,
        product_name,
        COALESCE(SUM(total_sales), 0) as total_sales,
        COALESCE(SUM(total_qty), 0) as total_qty,
        COALESCE(SUM(total_profit), 0) as total_profit
      FROM (
        SELECT 
          si.product_id as product_id,
          (CASE WHEN LENGTH(TRIM(si.product_name_snapshot)) > 0 THEN si.product_name_snapshot ELSE COALESCE(p.name, '') END) as product_name,
          COALESCE(si.total_line, 0) as total_sales,
          COALESCE(si.qty, 0) as total_qty,
          COALESCE(si.total_line, 0) - (COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)) as total_profit
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
        UNION ALL
        SELECT
          COALESCE(ri.product_id, si.product_id) as product_id,
          (CASE
            WHEN si.product_name_snapshot IS NOT NULL AND LENGTH(TRIM(si.product_name_snapshot)) > 0 THEN si.product_name_snapshot
            WHEN p.name IS NOT NULL AND LENGTH(TRIM(p.name)) > 0 THEN p.name
            ELSE COALESCE(ri.description, '')
          END) as product_name,
          -COALESCE(ri.total, 0) as total_sales,
          -COALESCE(ri.qty, 0) as total_qty,
          -(
            COALESCE(ri.total, 0)
            - (COALESCE(ri.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))
          ) as total_profit
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
      ) t
      GROUP BY product_id, product_name
      ORDER BY total_sales DESC
      LIMIT ?
    ''';

    final results =
        await db.rawQuery(query, [startMs, endMs, startMs, endMs, limit]);

    return results.map((row) {
      return TopProduct(
        productId: row['product_id'] as int? ?? 0,
        productName: row['product_name'] as String? ?? '',
        totalSales: (row['total_sales'] as num?)?.toDouble() ?? 0.0,
        totalQty: (row['total_qty'] as num?)?.toDouble() ?? 0.0,
        totalProfit: (row['total_profit'] as num?)?.toDouble() ?? 0.0,
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
        s.customer_id as client_id,
        s.customer_name_snapshot as client_name,
        COALESCE(SUM(s.total), 0) as total_spent,
        COALESCE(SUM(CASE WHEN s.kind IN ('invoice', 'sale') THEN 1 ELSE 0 END), 0) as purchase_count
      FROM ${DbTables.sales} s
      WHERE s.kind IN ('invoice', 'sale', 'return')
        AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
        AND s.deleted_at_ms IS NULL
        AND s.customer_id IS NOT NULL
        AND s.created_at_ms >= ?
        AND s.created_at_ms <= ?
      GROUP BY s.customer_id, s.customer_name_snapshot
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
        COALESCE(SUM(s.total), 0) as total_sales,
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
        AND created_at_ms >= ?
        AND created_at_ms <= ?
      ORDER BY created_at_ms DESC
    ''';

    final results = await db.rawQuery(query, [startMs, endMs]);

    return results.map((row) {
      return SaleRecord(
        id: row['id'] as int,
        customerId: row['customer_id'] as int?,
        localCode: row['local_code'] as String,
        kind: row['kind'] as String,
        createdAtMs: row['created_at_ms'] as int,
        customerName: row['customer_name_snapshot'] as String?,
        total: (row['total'] as num).toDouble(),
        paymentMethod: row['payment_method'] as String?,
      );
    }).toList();
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
        s.customer_id AS client_id,
        COALESCE(NULLIF(TRIM(s.customer_name_snapshot), ''), 'Cliente General') AS client_name,
        COALESCE(SUM(s.total), 0) AS total_sales,
        COALESCE(SUM(CASE WHEN COALESCE(LOWER(s.payment_method), '') = 'credit' THEN s.total ELSE 0 END), 0) AS total_credit,
        COALESCE(SUM(CASE WHEN s.kind IN ('invoice', 'sale') THEN 1 ELSE 0 END), 0) AS sales_count,
        COALESCE(MAX(s.created_at_ms), 0) AS last_purchase_at_ms
      FROM ${DbTables.sales} s
      WHERE s.kind IN ('invoice', 'sale', 'return')
        AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
        AND s.deleted_at_ms IS NULL
        AND s.customer_id IS NOT NULL
        AND s.created_at_ms >= ?
        AND s.created_at_ms <= ?
      GROUP BY s.customer_id, s.customer_name_snapshot
      ORDER BY total_sales DESC
      LIMIT ?
    ''';

    final rows = await db.rawQuery(query, [startMs, endMs, limit]);
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
            total: (row['total'] as num?)?.toDouble() ?? 0,
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

    final query =
        '''
      SELECT 
        method,
        COALESCE(SUM(amount), 0) as amount,
        COALESCE(SUM(count), 0) as count
      FROM (
        SELECT
          COALESCE(s.payment_method, 'Efectivo') as method,
          COALESCE(SUM(s.total), 0) as amount,
          COUNT(s.id) as count
        FROM ${DbTables.sales} s
        WHERE s.kind IN ('invoice', 'sale')
          AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND s.deleted_at_ms IS NULL
          AND s.created_at_ms >= ?
          AND s.created_at_ms <= ?
        GROUP BY method
        UNION ALL
        SELECT
          COALESCE(os.payment_method, 'Efectivo') as method,
          COALESCE(SUM(rs.total), 0) as amount,
          0 as count
        FROM ${DbTables.returns} r
        INNER JOIN ${DbTables.sales} rs ON r.return_sale_id = rs.id
        INNER JOIN ${DbTables.sales} os ON r.original_sale_id = os.id
        WHERE rs.kind = 'return'
          AND rs.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
          AND rs.deleted_at_ms IS NULL
          AND rs.created_at_ms >= ?
          AND rs.created_at_ms <= ?
        GROUP BY method
      ) t
      GROUP BY method
      ORDER BY amount DESC
    ''';

    final results = await db.rawQuery(query, [startMs, endMs, startMs, endMs]);
    var data = results.map((row) {
      String method = row['method'] as String? ?? 'Efectivo';
      if (method == 'cash' || method.isEmpty) method = 'Efectivo';
      if (method == 'card') method = 'Tarjeta';
      if (method == 'transfer') method = 'Transferencia';
      if (method == 'credit') method = 'Crédito';
      if (method == 'layaway') method = 'Apartado';

      return PaymentMethodData(
        method: method,
        amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
        count: (row['count'] as int?) ?? 0,
      );
    }).toList();

    data = data.where((entry) => entry.amount > 0).toList();

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
        COALESCE(SUM(total), 0) as total,
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





