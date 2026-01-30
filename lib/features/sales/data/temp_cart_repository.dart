import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'sale_item_model.dart';

/// Repositorio para manejar carritos temporales de ventas
class TempCartRepository {
  /// Guarda o actualiza un carrito temporal
  Future<int> saveCart({
    int? id,
    required String name,
    int? userId,
    int? clientId,
    required double discount,
    required bool itbisEnabled,
    required double itbisRate,
    required bool fiscalEnabled,
    String? discountTotalType,
    double? discountTotalValue,
    required List<SaleItemModel> items,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.transaction((txn) async {
      int cartId;

      if (id != null) {
        // Actualizar carrito existente
        await txn.update(
          DbTables.tempCarts,
          {
            'name': name,
            'user_id': userId,
            'client_id': clientId,
            'discount': discount,
            'itbis_enabled': itbisEnabled ? 1 : 0,
            'itbis_rate': itbisRate,
            'fiscal_enabled': fiscalEnabled ? 1 : 0,
            'discount_total_type': discountTotalType,
            'discount_total_value': discountTotalValue,
            'updated_at_ms': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        cartId = id;

        // Eliminar items antiguos
        await txn.delete(
          DbTables.tempCartItems,
          where: 'cart_id = ?',
          whereArgs: [cartId],
        );
      } else {
        // Crear nuevo carrito
        cartId = await txn.insert(DbTables.tempCarts, {
          'name': name,
          'user_id': userId,
          'client_id': clientId,
          'discount': discount,
          'itbis_enabled': itbisEnabled ? 1 : 0,
          'itbis_rate': itbisRate,
          'fiscal_enabled': fiscalEnabled ? 1 : 0,
          'discount_total_type': discountTotalType,
          'discount_total_value': discountTotalValue,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
      }

      // Insertar items
      for (final item in items) {
        await txn.insert(DbTables.tempCartItems, {
          'cart_id': cartId,
          'product_id': item.productId,
          'product_code_snapshot': item.productCodeSnapshot,
          'product_name_snapshot': item.productNameSnapshot,
          'qty': item.qty,
          'unit_price': item.unitPrice,
          'purchase_price_snapshot': item.purchasePriceSnapshot,
          'discount_line': item.discountLine,
          'total_line': item.totalLine,
          'created_at_ms': now,
        });
      }

      return cartId;
    });
  }

  /// Obtiene todos los carritos temporales
  Future<List<Map<String, dynamic>>> getAllCarts() async {
    final db = await AppDb.database;
    return await db.query(DbTables.tempCarts, orderBy: 'updated_at_ms DESC');
  }

  /// Obtiene los items de un carrito
  Future<List<SaleItemModel>> getCartItems(int cartId) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.tempCartItems,
      where: 'cart_id = ?',
      whereArgs: [cartId],
      orderBy: 'id ASC',
    );

    return maps.map((map) {
      return SaleItemModel(
        id: map['id'] as int?,
        saleId: 0,
        productId: map['product_id'] as int?,
        productCodeSnapshot: map['product_code_snapshot'] as String,
        productNameSnapshot: map['product_name_snapshot'] as String,
        qty: (map['qty'] as num).toDouble(),
        unitPrice: (map['unit_price'] as num).toDouble(),
        purchasePriceSnapshot: (map['purchase_price_snapshot'] as num)
            .toDouble(),
        discountLine: (map['discount_line'] as num).toDouble(),
        totalLine: (map['total_line'] as num).toDouble(),
        createdAtMs: map['created_at_ms'] as int,
      );
    }).toList();
  }

  /// Obtiene los items de multiples carritos en una sola consulta (mejor rendimiento).
  Future<Map<int, List<SaleItemModel>>> getCartItemsByCartIds(
    List<int> cartIds,
  ) async {
    if (cartIds.isEmpty) return {};
    final db = await AppDb.database;
    final placeholders = List.filled(cartIds.length, '?').join(',');
    final maps = await db.query(
      DbTables.tempCartItems,
      where: 'cart_id IN ($placeholders)',
      whereArgs: cartIds,
      orderBy: 'cart_id ASC, id ASC',
    );

    final grouped = <int, List<SaleItemModel>>{};
    for (final map in maps) {
      final cartId = map['cart_id'] as int? ?? 0;
      grouped.putIfAbsent(cartId, () => <SaleItemModel>[]).add(
        SaleItemModel(
          id: map['id'] as int?,
          saleId: 0,
          productId: map['product_id'] as int?,
          productCodeSnapshot: map['product_code_snapshot'] as String,
          productNameSnapshot: map['product_name_snapshot'] as String,
          qty: (map['qty'] as num).toDouble(),
          unitPrice: (map['unit_price'] as num).toDouble(),
          purchasePriceSnapshot:
              (map['purchase_price_snapshot'] as num).toDouble(),
          discountLine: (map['discount_line'] as num).toDouble(),
          totalLine: (map['total_line'] as num).toDouble(),
          createdAtMs: map['created_at_ms'] as int,
        ),
      );
    }

    return grouped;
  }

  /// Elimina un carrito temporal
  Future<void> deleteCart(int cartId) async {
    final db = await AppDb.database;
    await db.delete(DbTables.tempCarts, where: 'id = ?', whereArgs: [cartId]);
    // Los items se eliminan automáticamente por ON DELETE CASCADE
  }

  /// Elimina todos los carritos temporales
  Future<void> deleteAllCarts() async {
    final db = await AppDb.database;
    await db.delete(DbTables.tempCarts);
  }

  /// Obtiene un carrito por ID
  Future<Map<String, dynamic>?> getCartById(int cartId) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.tempCarts,
      where: 'id = ?',
      whereArgs: [cartId],
    );
    return maps.isEmpty ? null : maps.first;
  }
}
