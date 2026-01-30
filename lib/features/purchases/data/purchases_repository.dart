import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../products/models/stock_movement_model.dart';
import 'purchase_order_models.dart';

class PurchasesRepository {
  /// Crea una orden (manual o automática) con sus items, calculando totales.
  Future<int> createOrder({
    required int supplierId,
    required List<CreatePurchaseItemInput> items,
    required double taxRatePercent,
    String? notes,
    bool isAuto = false,
    int? purchaseDateMs,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Debe incluir al menos 1 producto');
    }

    final cleanedItems = <CreatePurchaseItemInput>[];
    for (final i in items) {
      if (i.qty <= 0) continue;
      if (i.unitCost < 0) continue;
      cleanedItems.add(i);
    }
    if (cleanedItems.isEmpty) {
      throw ArgumentError('Las cantidades deben ser mayores que 0');
    }

    final subtotal = cleanedItems.fold<double>(
      0.0,
      (sum, e) => sum + (e.qty * e.unitCost),
    );
    final taxAmount = subtotal * (taxRatePercent / 100.0);
    final total = subtotal + taxAmount;

    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction((txn) async {
      final orderId = await txn.insert(DbTables.purchaseOrders, {
        'supplier_id': supplierId,
        'status': 'PENDIENTE',
        'subtotal': subtotal,
        'tax_rate': taxRatePercent,
        'tax_amount': taxAmount,
        'total': total,
        'is_auto': isAuto ? 1 : 0,
        'notes': notes,
        'created_at_ms': now,
        'updated_at_ms': now,
        'received_at_ms': null,
        'purchase_date_ms': purchaseDateMs,
      });

      for (final item in cleanedItems) {
        await txn.insert(DbTables.purchaseOrderItems, {
          'order_id': orderId,
          'product_id': item.productId,
          'qty': item.qty,
          'unit_cost': item.unitCost,
          'total_line': item.qty * item.unitCost,
          'created_at_ms': now,
        });
      }

      return orderId;
    });
  }

  Future<List<PurchaseOrderSummaryDto>> listOrders({
    int? supplierId,
    String? status,
  }) async {
    final db = await AppDb.database;

    var where = '1=1';
    final args = <dynamic>[];

    if (supplierId != null) {
      where += ' AND o.supplier_id = ?';
      args.add(supplierId);
    }
    if (status != null && status.trim().isNotEmpty) {
      where += ' AND o.status = ?';
      args.add(status.trim());
    }

    final rows = await db.rawQuery('''
      SELECT o.*, s.name AS supplier_name
      FROM ${DbTables.purchaseOrders} o
      INNER JOIN ${DbTables.suppliers} s ON s.id = o.supplier_id
      WHERE $where
      ORDER BY o.created_at_ms DESC
    ''', args);

    return rows
        .map(
          (r) => PurchaseOrderSummaryDto(
            order: PurchaseOrderModel.fromMap(r),
            supplierName: (r['supplier_name'] as String?) ?? '',
          ),
        )
        .toList();
  }

  Future<PurchaseOrderDetailDto?> getOrderById(int orderId) async {
    final db = await AppDb.database;

    final headerRows = await db.rawQuery(
      '''
      SELECT o.*, s.name AS supplier_name, s.phone AS supplier_phone
      FROM ${DbTables.purchaseOrders} o
      INNER JOIN ${DbTables.suppliers} s ON s.id = o.supplier_id
      WHERE o.id = ?
      LIMIT 1
    ''',
      [orderId],
    );

    if (headerRows.isEmpty) return null;

    final header = headerRows.first;
    final order = PurchaseOrderModel.fromMap(header);

    final itemRows = await db.rawQuery(
      '''
      SELECT i.*, p.code AS product_code, p.name AS product_name
      FROM ${DbTables.purchaseOrderItems} i
      INNER JOIN ${DbTables.products} p ON p.id = i.product_id
      WHERE i.order_id = ?
      ORDER BY p.name ASC
    ''',
      [orderId],
    );

    final items = itemRows
        .map(
          (r) => PurchaseOrderItemDetailDto(
            item: PurchaseOrderItemModel.fromMap(r),
            productCode: (r['product_code'] as String?) ?? '',
            productName: (r['product_name'] as String?) ?? '',
          ),
        )
        .toList();

    return PurchaseOrderDetailDto(
      order: order,
      supplierName: (header['supplier_name'] as String?) ?? '',
      supplierPhone: header['supplier_phone'] as String?,
      items: items,
    );
  }

  /// Marca como RECIBIDA y actualiza inventario (stock + movimientos) en transacción.
  Future<void> markAsReceived(int orderId) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final orderRows = await txn.query(
        DbTables.purchaseOrders,
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) {
        throw ArgumentError('Orden no encontrada');
      }

      final status = (orderRows.first['status'] as String?) ?? 'PENDIENTE';
      if (status == 'RECIBIDA') {
        return; // idempotente
      }

      final items = await txn.query(
        DbTables.purchaseOrderItems,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      if (items.isEmpty) {
        throw ArgumentError('La orden no tiene detalle');
      }

      for (final item in items) {
        final productId = item['product_id'] as int;
        final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
        if (qty <= 0) continue;

        final productRows = await txn.query(
          DbTables.products,
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) continue;

        final currentStock =
            (productRows.first['stock'] as num?)?.toDouble() ?? 0.0;
        final newStock = currentStock + qty;

        await txn.update(
          DbTables.products,
          {'stock': newStock, 'updated_at_ms': now},
          where: 'id = ?',
          whereArgs: [productId],
        );

        await txn.insert(DbTables.stockMovements, {
          'product_id': productId,
          'type': StockMovementType.input.value,
          'quantity': qty,
          'note': 'Entrada por orden de compra #$orderId',
          'created_at_ms': now,
        });
      }

      await txn.update(
        DbTables.purchaseOrders,
        {'status': 'RECIBIDA', 'received_at_ms': now, 'updated_at_ms': now},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  /// Actualiza una orden PENDIENTE (cabecera + detalle). No modifica inventario.
  Future<void> updateOrder({
    required int orderId,
    required int supplierId,
    required List<CreatePurchaseItemInput> items,
    required double taxRatePercent,
    String? notes,
    int? purchaseDateMs,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Debe incluir al menos 1 producto');
    }

    final cleanedItems = <CreatePurchaseItemInput>[];
    for (final i in items) {
      if (i.qty <= 0) continue;
      if (i.unitCost < 0) continue;
      cleanedItems.add(i);
    }
    if (cleanedItems.isEmpty) {
      throw ArgumentError('Las cantidades deben ser mayores que 0');
    }

    final subtotal = cleanedItems.fold<double>(
      0.0,
      (sum, e) => sum + (e.qty * e.unitCost),
    );
    final taxAmount = subtotal * (taxRatePercent / 100.0);
    final total = subtotal + taxAmount;

    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final orderRows = await txn.query(
        DbTables.purchaseOrders,
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) {
        throw ArgumentError('Orden no encontrada');
      }

      final status = (orderRows.first['status'] as String?) ?? 'PENDIENTE';
      if (status.toUpperCase() == 'RECIBIDA') {
        throw ArgumentError('No se puede editar una orden ya recibida');
      }

      await txn.update(
        DbTables.purchaseOrders,
        {
          'supplier_id': supplierId,
          'subtotal': subtotal,
          'tax_rate': taxRatePercent,
          'tax_amount': taxAmount,
          'total': total,
          'notes': notes,
          'updated_at_ms': now,
          'purchase_date_ms': purchaseDateMs,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      // Asegurar que el detalle se reemplace completo.
      await txn.delete(
        DbTables.purchaseOrderItems,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      for (final item in cleanedItems) {
        await txn.insert(DbTables.purchaseOrderItems, {
          'order_id': orderId,
          'product_id': item.productId,
          'qty': item.qty,
          'unit_cost': item.unitCost,
          'total_line': item.qty * item.unitCost,
          'created_at_ms': now,
        });
      }
    });
  }

  /// Elimina una orden PENDIENTE (cabecera + detalle). No modifica inventario.
  Future<void> deleteOrder(int orderId) async {
    final db = await AppDb.database;

    await db.transaction((txn) async {
      final orderRows = await txn.query(
        DbTables.purchaseOrders,
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) {
        return;
      }

      final status = (orderRows.first['status'] as String?) ?? 'PENDIENTE';
      if (status.toUpperCase() == 'RECIBIDA') {
        throw ArgumentError('No se puede eliminar una orden ya recibida');
      }

      // Borrar detalle primero para evitar dependencia de FK settings.
      await txn.delete(
        DbTables.purchaseOrderItems,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      await txn.delete(
        DbTables.purchaseOrders,
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }
}

class _CreatePurchaseItemInput {
  final int productId;
  final double qty;
  final double unitCost;

  const _CreatePurchaseItemInput({
    required this.productId,
    required this.qty,
    required this.unitCost,
  });
}

typedef CreatePurchaseItemInput = _CreatePurchaseItemInput;

extension PurchasesCreateInputs on PurchasesRepository {
  CreatePurchaseItemInput itemInput({
    required int productId,
    required double qty,
    required double unitCost,
  }) {
    return _CreatePurchaseItemInput(
      productId: productId,
      qty: qty,
      unitCost: unitCost,
    );
  }
}
