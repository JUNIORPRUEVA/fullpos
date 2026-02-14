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

    final rows = await db.rawQuery(
      '''
      SELECT id, code, name, stock, stock_min, purchase_price
      FROM ${DbTables.products}
      WHERE deleted_at_ms IS NULL
        AND is_active = 1
        AND supplier_id = ?
        AND stock < stock_min
      ORDER BY name ASC
    ''',
      [supplierId],
    );

    return rows
        .map((r) {
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
        })
        .where((e) => e.suggestedQty > 0)
        .toList();
  }

  /// Productos agotados (stock <= 0) del suplidor.
  /// suggestedQty = max(minQty, stock_min) por defecto.
  Future<List<PurchaseOrderAutoSuggestion>> suggestOutOfStock({
    required int supplierId,
    double minQty = 1,
  }) async {
    final db = await AppDb.database;

    final rows = await db.rawQuery(
      '''
      SELECT id, code, name, stock, stock_min, purchase_price
      FROM ${DbTables.products}
      WHERE deleted_at_ms IS NULL
        AND is_active = 1
        AND supplier_id = ?
        AND stock <= 0
      ORDER BY name ASC
    ''',
      [supplierId],
    );

    return rows
        .map((r) {
          final stock = (r['stock'] as num?)?.toDouble() ?? 0.0;
          final minStock = (r['stock_min'] as num?)?.toDouble() ?? 0.0;
          final desired = (minStock > minQty ? minStock : minQty);
          return PurchaseOrderAutoSuggestion(
            productId: r['id'] as int,
            productCode: (r['code'] as String?) ?? '',
            productName: (r['name'] as String?) ?? '',
            currentStock: stock,
            minStock: minStock,
            suggestedQty: desired,
            unitCost: (r['purchase_price'] as num?)?.toDouble() ?? 0.0,
          );
        })
        .where((e) => e.suggestedQty > 0)
        .toList();
  }

  /// Sugerencia por ventas recientes.
  /// Calcula ventas por producto en los últimos [lookbackDays] y propone
  /// reponer para cubrir [replenishDays] de demanda.
  Future<List<PurchaseOrderAutoSuggestion>> suggestByRecentSales({
    required int supplierId,
    int lookbackDays = 30,
    int replenishDays = 14,
    double minQty = 1,
    int limit = 200,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now();
    final since = now
        .subtract(Duration(days: lookbackDays))
        .millisecondsSinceEpoch;

    final rows = await db.rawQuery(
      '''
      SELECT
        p.id,
        p.code,
        p.name,
        p.stock,
        p.stock_min,
        p.purchase_price,
        SUM(si.qty) AS sold_qty
      FROM ${DbTables.products} p
      INNER JOIN ${DbTables.saleItems} si ON si.product_id = p.id
      INNER JOIN ${DbTables.sales} s ON s.id = si.sale_id
      WHERE p.deleted_at_ms IS NULL
        AND p.is_active = 1
        AND p.supplier_id = ?
        AND s.deleted_at_ms IS NULL
        AND s.status = 'completed'
        AND s.created_at_ms >= ?
      GROUP BY p.id
      ORDER BY sold_qty DESC
      LIMIT ?
    ''',
      [supplierId, since, limit],
    );

    final safeLookback = lookbackDays <= 0 ? 1 : lookbackDays;
    final safeReplenish = replenishDays <= 0 ? 1 : replenishDays;

    return rows
        .map((r) {
          final stock = (r['stock'] as num?)?.toDouble() ?? 0.0;
          final minStock = (r['stock_min'] as num?)?.toDouble() ?? 0.0;
          final soldQty = (r['sold_qty'] as num?)?.toDouble() ?? 0.0;

          final daily = soldQty / safeLookback;
          final target = daily * safeReplenish;
          final desired = target > minStock ? target : minStock;
          final suggested = desired - stock;

          final effective = suggested <= 0
              ? 0.0
              : (suggested < minQty ? minQty : suggested);

          return PurchaseOrderAutoSuggestion(
            productId: r['id'] as int,
            productCode: (r['code'] as String?) ?? '',
            productName: (r['name'] as String?) ?? '',
            currentStock: stock,
            minStock: minStock,
            suggestedQty: effective,
            unitCost: (r['purchase_price'] as num?)?.toDouble() ?? 0.0,
          );
        })
        .where((e) => e.suggestedQty > 0)
        .toList();
  }
}
