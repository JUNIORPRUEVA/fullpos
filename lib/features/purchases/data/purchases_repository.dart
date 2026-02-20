import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../products/models/stock_movement_model.dart';
import 'purchase_order_models.dart';
import 'package:sqflite/sqflite.dart';

class PurchasesRepository {
  static double _normalizeQty(double value) =>
      double.parse(value.toStringAsFixed(6));
  static double _money2(double value) => double.parse(value.toStringAsFixed(2));

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
      final name = i.productNameSnapshot.trim();
      if (name.isEmpty) continue;
      cleanedItems.add(i);
    }
    if (cleanedItems.isEmpty) {
      throw ArgumentError('Las cantidades deben ser mayores que 0');
    }

    final subtotal = _money2(
      cleanedItems.fold<double>(0.0, (sum, e) => sum + (e.qty * e.unitCost)),
    );
    final taxAmount = _money2(subtotal * (taxRatePercent / 100.0));
    final total = _money2(subtotal + taxAmount);

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
          'product_code_snapshot': item.productCodeSnapshot.trim(),
          'product_name_snapshot': item.productNameSnapshot.trim(),
          'qty': item.qty,
          'received_qty': 0,
          'unit_cost': item.unitCost,
          'total_line': _money2(item.qty * item.unitCost),
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
      SELECT i.*
      FROM ${DbTables.purchaseOrderItems} i
      WHERE i.order_id = ?
      ORDER BY i.product_name_snapshot ASC
    ''',
      [orderId],
    );

    final items = itemRows
        .map(
          (r) => PurchaseOrderItemDetailDto(
            item: PurchaseOrderItemModel.fromMap(r),
            productCode: (r['product_code_snapshot'] as String?) ?? '',
            productName: (r['product_name_snapshot'] as String?) ?? '',
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
        final itemId = item['id'] as int?;
        final productId = item['product_id'] as int?;
        if (productId == null || productId <= 0) continue;
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

        // Marcar item como recibido completamente.
        if (itemId != null && itemId > 0) {
          await txn.update(
            DbTables.purchaseOrderItems,
            {'received_qty': qty},
            where: 'id = ? AND order_id = ?',
            whereArgs: [itemId, orderId],
          );
        }
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
      final name = i.productNameSnapshot.trim();
      if (name.isEmpty) continue;
      cleanedItems.add(i);
    }
    if (cleanedItems.isEmpty) {
      throw ArgumentError('Las cantidades deben ser mayores que 0');
    }

    final subtotal = _money2(
      cleanedItems.fold<double>(0.0, (sum, e) => sum + (e.qty * e.unitCost)),
    );
    final taxAmount = _money2(subtotal * (taxRatePercent / 100.0));
    final total = _money2(subtotal + taxAmount);

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
      final normalized = status.trim().toUpperCase();
      if (normalized == 'RECIBIDA' || normalized == 'PARCIAL') {
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
          'product_code_snapshot': item.productCodeSnapshot.trim(),
          'product_name_snapshot': item.productNameSnapshot.trim(),
          'qty': item.qty,
          'received_qty': 0,
          'unit_cost': item.unitCost,
          'total_line': _money2(item.qty * item.unitCost),
          'created_at_ms': now,
        });
      }
    });
  }

  /// Recibe (parcial o total) un solo item de la orden.
  ///
  /// - Incrementa stock del producto (si existe product_id)
  /// - Registra movimiento de stock
  /// - Actualiza received_qty del item
  /// - Actualiza estado de la orden: PARCIAL o RECIBIDA
  Future<void> receiveItem({
    required int orderId,
    required int itemId,
    required double qtyToReceive,
  }) async {
    final requestedQty = _normalizeQty(qtyToReceive);
    if (requestedQty <= 0) {
      throw ArgumentError('La cantidad a recibir debe ser mayor que 0');
    }

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
      if (status.trim().toUpperCase() == 'RECIBIDA') {
        throw ArgumentError('La orden ya está recibida');
      }

      final itemRows = await txn.query(
        DbTables.purchaseOrderItems,
        where: 'id = ? AND order_id = ?',
        whereArgs: [itemId, orderId],
        limit: 1,
      );
      if (itemRows.isEmpty) {
        throw ArgumentError('Item no encontrado');
      }

      final item = itemRows.first;
      final orderedQty = _normalizeQty(
        (item['qty'] as num?)?.toDouble() ?? 0.0,
      );
      final receivedQty = _normalizeQty(
        (item['received_qty'] as num?)?.toDouble() ?? 0.0,
      );
      final remaining = _normalizeQty(orderedQty - receivedQty);
      final productId = item['product_id'] as int?;

      if (orderedQty <= 0) {
        throw ArgumentError('Cantidad inválida en el item');
      }
      if (remaining <= 0) {
        throw ArgumentError('Este producto ya está recibido');
      }
      if (productId == null || productId <= 0) {
        throw ArgumentError(
          'Este ítem no tiene producto creado. Créalo y vuelve a recibir.',
        );
      }

      const tolerance = 0.0005;
      if (requestedQty - remaining > tolerance) {
        throw ArgumentError(
          'No puede recibir más de lo pendiente. Pendiente: ${remaining.toStringAsFixed(2)}',
        );
      }

      final appliedQty = requestedQty > remaining ? remaining : requestedQty;
      final newReceivedQty = _normalizeQty(receivedQty + appliedQty);

      // Actualizar received_qty.
      await txn.update(
        DbTables.purchaseOrderItems,
        {'received_qty': newReceivedQty},
        where: 'id = ? AND order_id = ?',
        whereArgs: [itemId, orderId],
      );

      // Actualizar stock del producto vinculado.
      final productRows = await txn.query(
        DbTables.products,
        columns: ['stock'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw ArgumentError('El producto vinculado no existe en inventario');
      }

      final currentStock = _normalizeQty(
        (productRows.first['stock'] as num?)?.toDouble() ?? 0.0,
      );
      final newStock = _normalizeQty(currentStock + appliedQty);

      await txn.update(
        DbTables.products,
        {'stock': newStock, 'updated_at_ms': now},
        where: 'id = ?',
        whereArgs: [productId],
      );

      await txn.insert(DbTables.stockMovements, {
        'product_id': productId,
        'type': StockMovementType.input.value,
        'quantity': appliedQty,
        'note': 'Entrada por recepción de orden de compra #$orderId',
        'created_at_ms': now,
      });

      // Recalcular estado de la orden.
      final allItems = await txn.query(
        DbTables.purchaseOrderItems,
        columns: ['qty', 'received_qty'],
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      var allReceived = true;
      for (final r in allItems) {
        final q = (r['qty'] as num?)?.toDouble() ?? 0.0;
        final rq = (r['received_qty'] as num?)?.toDouble() ?? 0.0;
        if (q <= 0) continue;
        if (rq + 1e-9 < q) {
          allReceived = false;
          break;
        }
      }

      if (allReceived) {
        await txn.update(
          DbTables.purchaseOrders,
          {'status': 'RECIBIDA', 'received_at_ms': now, 'updated_at_ms': now},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      } else {
        await txn.update(
          DbTables.purchaseOrders,
          {'status': 'PARCIAL', 'received_at_ms': null, 'updated_at_ms': now},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }
    });
  }

  /// Vincula un producto existente a un ítem de orden de compra.
  Future<void> attachProductToOrderItem({
    required int orderId,
    required int itemId,
    required int productId,
    required String productCodeSnapshot,
    required String productNameSnapshot,
  }) async {
    final db = await AppDb.database;

    await db.transaction((txn) async {
      final orderRows = await txn.query(
        DbTables.purchaseOrders,
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) {
        throw ArgumentError('Orden no encontrada');
      }

      final itemRows = await txn.query(
        DbTables.purchaseOrderItems,
        columns: ['id', 'received_qty'],
        where: 'id = ? AND order_id = ?',
        whereArgs: [itemId, orderId],
        limit: 1,
      );
      if (itemRows.isEmpty) {
        throw ArgumentError('Item no encontrado');
      }

      final alreadyReceived =
          (itemRows.first['received_qty'] as num?)?.toDouble() ?? 0.0;
      if (alreadyReceived > 0) {
        throw ArgumentError(
          'No se puede vincular: el ítem ya tiene recepción registrada.',
        );
      }

      final productRows = await txn.query(
        DbTables.products,
        columns: ['id'],
        where: 'id = ? AND deleted_at_ms IS NULL',
        whereArgs: [productId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw ArgumentError('El producto a vincular no existe o está inactivo');
      }

      await txn.update(
        DbTables.purchaseOrderItems,
        {
          'product_id': productId,
          'product_code_snapshot': productCodeSnapshot.trim(),
          'product_name_snapshot': productNameSnapshot.trim(),
        },
        where: 'id = ? AND order_id = ?',
        whereArgs: [itemId, orderId],
      );
    });
  }

  /// Anula recepción: revierte inventario según received_qty y deja la orden como PENDIENTE.
  Future<void> cancelReceipt(int orderId) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final orderRows = await txn.query(
        DbTables.purchaseOrders,
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) return;

      final items = await txn.query(
        DbTables.purchaseOrderItems,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      if (items.isEmpty) return;

      // Validación previa: evitar stock negativo.
      for (final item in items) {
        final receivedQty = (item['received_qty'] as num?)?.toDouble() ?? 0.0;
        if (receivedQty <= 0) continue;

        final productId = item['product_id'] as int?;
        if (productId == null || productId <= 0) continue;

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
        if (currentStock + 1e-9 < receivedQty) {
          throw ArgumentError(
            'No se puede anular: el stock actual es menor que lo recibido (producto #$productId).',
          );
        }
      }

      // Revertir stock y resetear received_qty.
      for (final item in items) {
        final receivedQty = (item['received_qty'] as num?)?.toDouble() ?? 0.0;
        if (receivedQty <= 0) continue;

        final productId = item['product_id'] as int?;
        if (productId != null && productId > 0) {
          final productRows = await txn.query(
            DbTables.products,
            columns: ['stock'],
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          );
          if (productRows.isNotEmpty) {
            final currentStock =
                (productRows.first['stock'] as num?)?.toDouble() ?? 0.0;
            final newStock = currentStock - receivedQty;

            await txn.update(
              DbTables.products,
              {'stock': newStock, 'updated_at_ms': now},
              where: 'id = ?',
              whereArgs: [productId],
            );

            await txn.insert(DbTables.stockMovements, {
              'product_id': productId,
              'type': StockMovementType.output.value,
              'quantity': receivedQty,
              'note':
                  'Salida por anulación de recepción de orden de compra #$orderId',
              'created_at_ms': now,
            });
          }
        }

        final itemId = item['id'] as int?;
        if (itemId != null && itemId > 0) {
          await txn.update(
            DbTables.purchaseOrderItems,
            {'received_qty': 0},
            where: 'id = ? AND order_id = ?',
            whereArgs: [itemId, orderId],
          );
        }
      }

      await txn.update(
        DbTables.purchaseOrders,
        {'status': 'PENDIENTE', 'received_at_ms': null, 'updated_at_ms': now},
        where: 'id = ?',
        whereArgs: [orderId],
      );
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
      final normalized = status.trim().toUpperCase();
      if (normalized != 'PENDIENTE') {
        throw ArgumentError('Solo se puede eliminar una orden PENDIENTE');
      }

      // Defensa extra: si por alguna razón hay recepción parcial, no permitir.
      final receivedCount = Sqflite.firstIntValue(
        await txn.rawQuery(
          'SELECT COUNT(*) FROM ${DbTables.purchaseOrderItems} WHERE order_id = ? AND received_qty > 0',
          [orderId],
        ),
      );
      if ((receivedCount ?? 0) > 0) {
        throw ArgumentError(
          'No se puede eliminar: la orden tiene productos recibidos (anula recepción primero).',
        );
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
  final int? productId;
  final String productCodeSnapshot;
  final String productNameSnapshot;
  final double qty;
  final double unitCost;

  const _CreatePurchaseItemInput({
    required this.productId,
    required this.productCodeSnapshot,
    required this.productNameSnapshot,
    required this.qty,
    required this.unitCost,
  });
}

typedef CreatePurchaseItemInput = _CreatePurchaseItemInput;

extension PurchasesCreateInputs on PurchasesRepository {
  CreatePurchaseItemInput itemInput({
    required int? productId,
    String productCodeSnapshot = '',
    required String productNameSnapshot,
    required double qty,
    required double unitCost,
  }) {
    return _CreatePurchaseItemInput(
      productId: productId,
      productCodeSnapshot: productCodeSnapshot,
      productNameSnapshot: productNameSnapshot,
      qty: qty,
      unitCost: unitCost,
    );
  }
}
