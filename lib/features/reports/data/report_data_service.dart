import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../sales/data/sales_model.dart';

class DateFilter {
  DateFilter({required DateTime start, required DateTime end})
    : start = DateTime(start.year, start.month, start.day),
      end = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

  final DateTime start;
  final DateTime end;
}

class ReportExpense {
  ReportExpense({
    required this.id,
    required this.amount,
    required this.createdAtMs,
    this.note,
  });

  final int id;
  final double amount;
  final int createdAtMs;
  final String? note;
}

class ReportData {
  ReportData({
    required this.sales,
    required this.expenses,
    required this.totalSales,
    required this.totalCost,
    required this.totalExpenses,
    required this.grossProfit,
    required this.profit,
  });

  final List<SaleModel> sales;
  final List<ReportExpense> expenses;
  final double totalSales;
  final double totalCost;
  final double totalExpenses;
  final double grossProfit;
  final double profit;
}

class ReportDataService {
  ReportDataService._();

  static Future<ReportData> getReportData(DateFilter filter) async {
    final db = await AppDb.database;
    final startMs = filter.start.millisecondsSinceEpoch;
    final endMs = filter.end.millisecondsSinceEpoch;

    final saleRows = await db.query(
      DbTables.sales,
      where:
          "status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED') AND kind IN ('invoice', 'sale') AND deleted_at_ms IS NULL AND created_at_ms >= ? AND created_at_ms <= ?",
      whereArgs: [startMs, endMs],
      orderBy: 'created_at_ms DESC',
    );

    final sales = saleRows.map(SaleModel.fromMap).toList();

    final expenseRows = await db.rawQuery(
      '''
        SELECT id, amount, note, created_at_ms
        FROM ${DbTables.cashMovements}
        WHERE type = 'OUT'
          AND COALESCE(movement_type, 'expense') = 'expense'
          AND COALESCE(affects_profit, 1) = 1
          AND created_at_ms >= ?
          AND created_at_ms <= ?
        ORDER BY created_at_ms ASC
      ''',
      [startMs, endMs],
    );

    final expenses = expenseRows
        .map(
          (row) => ReportExpense(
            id: row['id'] as int,
            amount: (row['amount'] as num?)?.toDouble() ?? 0,
            createdAtMs: row['created_at_ms'] as int,
            note: row['note'] as String?,
          ),
        )
        .toList();

    final totalSalesRows = await db.rawQuery(
      '''
        SELECT
          COALESCE(SUM(
            CASE
              WHEN kind = 'return' THEN -ABS(COALESCE(total, 0))
              ELSE COALESCE(total, 0)
            END
          ), 0) as total
        FROM ${DbTables.sales}
        WHERE status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
          AND kind IN ('invoice', 'sale', 'return')
          AND deleted_at_ms IS NULL
          AND created_at_ms >= ?
          AND created_at_ms <= ?
      ''',
      [startMs, endMs],
    );
    final totalSales =
        (totalSalesRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final soldCostRows = await db.rawQuery(
      '''
        SELECT
          COALESCE(SUM(
            COALESCE(si.qty, 0) *
            COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)
          ), 0) as total
        FROM ${DbTables.saleItems} si
        INNER JOIN ${DbTables.sales} s ON si.sale_id = s.id
        LEFT JOIN ${DbTables.products} p
          ON (si.product_id = p.id)
          OR (
            si.product_id IS NULL
            AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
          )
        WHERE s.status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
          AND s.kind IN ('invoice', 'sale')
          AND s.deleted_at_ms IS NULL
          AND s.created_at_ms >= ?
          AND s.created_at_ms <= ?
      ''',
      [startMs, endMs],
    );
    final soldCost = (soldCostRows.first['total'] as num?)?.toDouble() ?? 0.0;

    final returnedCostRows = await db.rawQuery(
      '''
        SELECT
          COALESCE(SUM(
            COALESCE(ri.qty, 0) *
            COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)
          ), 0) as total
        FROM ${DbTables.returnItems} ri
        INNER JOIN ${DbTables.returns} r ON ri.return_id = r.id
        INNER JOIN ${DbTables.sales} rs ON r.return_sale_id = rs.id
        LEFT JOIN ${DbTables.saleItems} si ON ri.sale_item_id = si.id
        LEFT JOIN ${DbTables.products} p
          ON COALESCE(ri.product_id, si.product_id) = p.id
        WHERE rs.status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
          AND rs.kind = 'return'
          AND rs.deleted_at_ms IS NULL
          AND rs.created_at_ms >= ?
          AND rs.created_at_ms <= ?
      ''',
      [startMs, endMs],
    );
    final returnedCost =
        (returnedCostRows.first['total'] as num?)?.toDouble() ?? 0.0;
    final totalCost = soldCost - returnedCost;

    final totalExpenses = expenses.fold<double>(
      0,
      (sum, expense) => sum + expense.amount,
    );
    final grossProfit = totalSales - totalCost;

    return ReportData(
      sales: sales,
      expenses: expenses,
      totalSales: totalSales,
      totalCost: totalCost,
      totalExpenses: totalExpenses,
      grossProfit: grossProfit,
      profit: grossProfit,
    );
  }
}
