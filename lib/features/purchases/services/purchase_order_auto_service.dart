import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';

class PurchaseOrderAutoSuggestion {
  final int productId;
  final String productCode;
  final String productName;
  final double currentStock;
  final double minStock;
  final double suggestedQty;
  final double unitCost;

  const PurchaseOrderAutoSuggestion({
    required this.productId,
    required this.productCode,
    required this.productName,
    required this.currentStock,
    required this.minStock,
    required this.suggestedQty,
    required this.unitCost,
  });
}

class PurchaseOrderAutoService {
  /// Retorna productos del suplidor con stock por debajo del mínimo.
  /// suggestedQty = max(0, stock_min - stock)
  Future<List<PurchaseOrderAutoSuggestion>> suggestBySupplier({
    required int supplierId,
  }) async {
    final db = await AppDb.database;

    final rows = await db.rawQuery('''
      SELECT id, code, name, stock, stock_min, purchase_price
      FROM ${DbTables.products}
      WHERE deleted_at_ms IS NULL
        AND is_active = 1
        AND supplier_id = ?
        AND stock < stock_min
      ORDER BY name ASC
    ''', [supplierId]);

    return rows.map((r) {
      final stock = (r['stock'] as num?)?.toDouble() ?? 0.0;
      final minStock = (r['stock_min'] as num?)?.toDouble() ?? 0.0;
      final suggested = (minStock - stock);
      return PurchaseOrderAutoSuggestion(
        productId: r['id'] as int,
        productCode: (r['code'] as String?) ?? '',
        productName: (r['name'] as String?) ?? '',
        currentStock: stock,
        minStock: minStock,
        suggestedQty: suggested < 0 ? 0 : suggested,
        unitCost: (r['purchase_price'] as num?)?.toDouble() ?? 0.0,
      );
    }).where((e) => e.suggestedQty > 0).toList();
  }
}
