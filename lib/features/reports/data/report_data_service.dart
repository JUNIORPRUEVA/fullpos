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
    required this.totalExpenses,
    required this.profit,
  });

  final List<SaleModel> sales;
  final List<ReportExpense> expenses;
  final double totalSales;
  final double totalExpenses;
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

    final totalSales = sales.fold<double>(0, (sum, sale) => sum + sale.total);
    final totalExpenses = expenses.fold<double>(
      0,
      (sum, expense) => sum + expense.amount,
    );

    return ReportData(
      sales: sales,
      expenses: expenses,
      totalSales: totalSales,
      totalExpenses: totalExpenses,
      profit: totalSales - totalExpenses,
    );
  }
}
