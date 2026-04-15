import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/services/cloud_sync_service.dart';
import 'sales_model.dart';

class ReturnsRepository {
  ReturnsRepository._();

  static Future<({String status, bool isFullyRefunded})> _resolveRefundState(
    Transaction txn,
    int originalSaleId,
  ) async {
    final saleItems = await txn.query(
      DbTables.saleItems,
      columns: ['id', 'qty'],
      where: 'sale_id = ?',
      whereArgs: [originalSaleId],
    );

    if (saleItems.isEmpty) {
      return (status: 'REFUNDED', isFullyRefunded: true);
    }

    final returnedRows = await txn.rawQuery(
      '''
      SELECT ri.sale_item_id, COALESCE(SUM(ri.qty), 0) AS returned_qty
      FROM ${DbTables.returnItems} ri
      JOIN ${DbTables.returns} r ON r.id = ri.return_id
      WHERE r.original_sale_id = ?
      GROUP BY ri.sale_item_id
      ''',
      [originalSaleId],
    );

    final returnedQtyBySaleItemId = <int, double>{};
    for (final row in returnedRows) {
      final saleItemId = row['sale_item_id'] as int?;
      if (saleItemId == null) continue;
      returnedQtyBySaleItemId[saleItemId] =
          (row['returned_qty'] as num?)?.toDouble() ?? 0.0;
    }

    var hasReturnedQty = false;
    var isFullyRefunded = true;
    for (final saleItem in saleItems) {
      final saleItemId = saleItem['id'] as int?;
      final originalQty = (saleItem['qty'] as num?)?.toDouble() ?? 0.0;
      final returnedQty =
          saleItemId == null ? 0.0 : (returnedQtyBySaleItemId[saleItemId] ?? 0.0);
      if (returnedQty > 0.0001) {
        hasReturnedQty = true;
      }
      if (returnedQty + 0.0001 < originalQty) {
        isFullyRefunded = false;
      }
    }

    if (!hasReturnedQty) {
      isFullyRefunded = false;
    }

    return (
      status: isFullyRefunded ? 'REFUNDED' : 'PARTIAL_REFUND',
      isFullyRefunded: isFullyRefunded,
    );
  }

  /// Crea una devolución completa con stock restoration
  static Future<int> createReturn({
    required int originalSaleId,
    required List<Map<String, dynamic>> returnItems,
    int? cashSessionId,
    String? note,
  }) async {
    final db = await AppDb.database;

    // Leer la venta original fuera de la transacción evita bloqueos
    // (no mezclar `db.*` dentro de `txn` en sqflite).
    final originalSaleRows = await db.query(
      DbTables.sales,
      where: 'id = ?',
      whereArgs: [originalSaleId],
      limit: 1,
    );

    if (originalSaleRows.isEmpty) {
      throw Exception('Venta original no encontrada');
    }

    final original = SaleModel.fromMap(originalSaleRows.first);

    final returnSaleId = await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Calcular totales de devolución
      double returnSubtotal = 0.0;
      for (final item in returnItems) {
        final qty = (item['qty'] as num).toDouble();
        final price = (item['price'] as num).toDouble();
        final lineTotal = qty * price;
        returnSubtotal += lineTotal;
      }

      // Generar código de devolución
      final returnCode =
          'DEV-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';

      // Insertar venta de devolución (con valores negativo para offset)
      final returnSaleId = await txn.insert(DbTables.sales, {
        'local_code': returnCode,
        'kind': 'return',
        'status': 'completed',
        'customer_id': original.customerId,
        'customer_name_snapshot': original.customerNameSnapshot,
        'customer_phone_snapshot': original.customerPhoneSnapshot,
        'customer_rnc_snapshot': original.customerRncSnapshot,
        'itbis_enabled': original.itbisEnabled,
        'itbis_rate': original.itbisRate,
        'discount_total': 0.0,
        'subtotal': -returnSubtotal,
        'itbis_amount': original.itbisEnabled == 1
            ? -(returnSubtotal * original.itbisRate)
            : 0.0,
        'total':
            -(returnSubtotal +
                (original.itbisEnabled == 1
                    ? returnSubtotal * original.itbisRate
                    : 0.0)),
        'payment_method': 'return',
        'paid_amount': 0.0,
        'change_amount': 0.0,
        'electronic_invoice_enabled': 0,
        'electronic_invoice_code': null,
        'electronic_document_type': null,
        // La devolución debe impactar la caja del turno ACTUAL (donde sale el efectivo),
        // aunque el ticket original sea de otro turno.
        'session_id': cashSessionId,
        'cash_session_id': cashSessionId,
        'created_at_ms': now,
        'updated_at_ms': now,
      });

      // Registrar relación de devolución primero (para obtener return_id)
      final returnId = await txn.insert(DbTables.returns, {
        'original_sale_id': originalSaleId,
        'return_sale_id': returnSaleId,
        'note': note,
        'created_at_ms': now,
      });

      // Insertar items de devolución y restaurar stock
      for (final item in returnItems) {
        await txn.insert(DbTables.returnItems, {
          // FK apunta a returns.id, no a sales.id
          'return_id': returnId,
          'sale_item_id': item['sale_item_id'],
          'product_id': item['product_id'],
          'description': item['description'],
          'qty': item['qty'],
          'price': item['price'],
          'total':
              (item['qty'] as num).toDouble() *
              (item['price'] as num).toDouble(),
        });

        // Restaurar stock automáticamente
        if (item['product_id'] != null) {
          final productId = item['product_id'] as int;
          final qty = (item['qty'] as num).toDouble();

          // Sumar stock
          await txn.rawUpdate(
            'UPDATE ${DbTables.products} SET stock = stock + ?, updated_at_ms = ? WHERE id = ?',
            [qty, now, productId],
          );

          // Registrar movimiento de stock
          await txn.insert(DbTables.stockMovements, {
            'product_id': productId,
            // Usar el mismo valor que el resto del sistema (StockMovementType.input.value)
            'type': 'in',
            'quantity': qty,
            'note': 'Devolución #$returnId - Original: ${original.localCode}',
            'created_at_ms': now,
          });
        }
      }

      final refundState = await _resolveRefundState(txn, originalSaleId);
      await txn.update(
        DbTables.sales,
        {
          'status': refundState.status,
          'updated_at_ms': now,
          'deleted_at_ms': refundState.isFullyRefunded ? now : null,
        },
        where: 'id = ?',
        whereArgs: [originalSaleId],
      );

      return returnSaleId;
    });

    CloudSyncService.instance.scheduleProductsSyncSoon();
    unawaited(
      CloudSyncService.instance.syncReturnsNow(reason: 'return_applied'),
    );
    unawaited(
      CloudSyncService.instance.syncSalesNow(reason: 'return_applied'),
    );

    return returnSaleId;
  }

  /// Lista devoluciones con filtros
  static Future<List<Map<String, dynamic>>> listReturns({
    int? clientId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await AppDb.database;

    String where = '1=1';
    List<dynamic> args = [];

    if (clientId != null) {
      where += ' AND s.customer_id = ?';
      args.add(clientId);
    }

    if (dateFrom != null) {
      final fromMs = dateFrom.millisecondsSinceEpoch;
      where += ' AND s.created_at_ms >= ?';
      args.add(fromMs);
    }

    if (dateTo != null) {
      final toMs = dateTo.add(Duration(days: 1)).millisecondsSinceEpoch;
      where += ' AND s.created_at_ms < ?';
      args.add(toMs);
    }

    final result = await db.rawQuery(
      '''SELECT r.*, s.local_code, s.customer_name_snapshot, s.total, s.created_at_ms, s.session_id
         FROM ${DbTables.returns} r
         JOIN ${DbTables.sales} s ON r.return_sale_id = s.id
         WHERE $where
         ORDER BY r.created_at_ms DESC''',
      args,
    );

    return result;
  }

  /// Obtiene items de una devolución
  static Future<List<Map<String, dynamic>>> getReturnItems(int returnId) async {
    final db = await AppDb.database;

    return await db.query(
      DbTables.returnItems,
      where: 'return_id = ?',
      whereArgs: [returnId],
    );
  }
}
