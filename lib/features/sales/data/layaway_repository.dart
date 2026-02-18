import 'package:sqflite/sqflite.dart';
import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/validation/business_rules.dart';
import 'sales_repository.dart';
import 'sales_model.dart';
import 'sale_item_model.dart' as new_models;

class LayawayPaymentResult {
  final int paymentId;
  final double totalPaid;
  final double pendingAmount;
  final String status;

  const LayawayPaymentResult({
    required this.paymentId,
    required this.totalPaid,
    required this.pendingAmount,
    required this.status,
  });
}

class LayawayRepository {
  LayawayRepository._();

  static Future<int> createLayawaySale({
    required String localCode,
    required String kind,
    required List<dynamic> items,
    required bool itbisEnabled,
    required double itbisRate,
    required double discountTotal,
    double? subtotalOverride,
    double? itbisAmountOverride,
    double? totalOverride,
    bool fiscalEnabled = false,
    String? ncfFull,
    String? ncfType,
    int? sessionId,
    int? customerId,
    String? customerName,
    String? customerPhone,
    double initialPayment = 0.0,
    String? note,
    bool enforceLocalCodeIdempotency = false,
  }) async {
    // Validar abono inicial mínimo 30%
    final effectiveTotal = totalOverride ??
        (() {
          double tmp = 0;
          for (final item in items) {
            if (item is SaleItemModel) {
              tmp += item.totalLine;
            } else if (item is new_models.SaleItemModel) {
              tmp += item.totalLine;
            } else if (item is Map && item['total_line'] != null) {
              final v = item['total_line'];
              tmp += v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
            }
          }
          final subtotal = tmp - discountTotal;
          final itbisAmountCalc = itbisAmountOverride ??
              (itbisEnabled ? (subtotal * itbisRate) : 0.0);
          return subtotal + itbisAmountCalc;
        })();
    final minDown = (effectiveTotal * 0.30).clamp(0, double.infinity);
    if (initialPayment + 1e-6 < minDown) {
      throw BusinessRuleException(
        code: 'layaway_min_down_payment',
        messageUser:
            'El abono inicial debe ser al menos el 30% (${minDown.toStringAsFixed(2)})',
        messageDev: 'Layaway initial payment below 30%: $initialPayment < $minDown',
      );
    }

    final saleId = await SalesRepository.createSale(
      localCode: localCode,
      kind: kind,
      items: items,
      itbisEnabled: itbisEnabled,
      itbisRate: itbisRate,
      discountTotal: discountTotal,
      subtotalOverride: subtotalOverride,
      itbisAmountOverride: itbisAmountOverride,
      totalOverride: totalOverride,
      paymentMethod: 'layaway',
      sessionId: sessionId,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      fiscalEnabled: fiscalEnabled,
      ncfFull: ncfFull,
      ncfType: ncfType,
      paidAmount: 0.0,
      changeAmount: 0.0,
      status: 'LAYAWAY',
      stockUpdateMode: StockUpdateMode.reserve,
      enforceLocalCodeIdempotency: enforceLocalCodeIdempotency,
    );

    if (initialPayment > 0) {
      await registerLayawayPayment(
        saleId: saleId,
        clientId: customerId,
        amount: initialPayment,
        method: 'cash',
        note: note,
        sessionId: sessionId,
      );
    }

    return saleId;
  }

  static Future<LayawayPaymentResult> registerLayawayPayment({
    required int saleId,
    int? clientId,
    required double amount,
    required String method,
    String? note,
    int? userId,
    int? sessionId,
  }) async {
    return DbHardening.instance.runDbSafe<LayawayPaymentResult>(() async {
      final db = await AppDb.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      return db.transaction((txn) async {
        final saleRows = await txn.query(
          DbTables.sales,
          where: 'id = ?',
          whereArgs: [saleId],
          limit: 1,
        );
        if (saleRows.isEmpty) {
          throw BusinessRuleException(
            code: 'sale_not_found',
            messageUser: 'No se encontrÃ³ el apartado.',
            messageDev: 'Layaway sale not found: saleId=$saleId',
          );
        }

        final sale = saleRows.first;
        final resolvedClientId =
            clientId ?? (sale['customer_id'] as int?);
        final resolvedSessionId =
            sessionId ??
            (sale['cash_session_id'] as int?) ??
            (sale['session_id'] as int?);
        if (resolvedSessionId == null) {
          throw BusinessRuleException(
            code: 'layaway_no_session',
            messageUser: 'Debe abrir caja para registrar abonos de apartado.',
            messageDev: 'No cash session for layaway payment saleId=$saleId',
          );
        }

        final paymentId = await txn.insert(DbTables.layawayPayments, {
          'sale_id': saleId,
          'client_id': resolvedClientId,
          'amount': amount,
          'method': method,
          'note': note,
          'created_at_ms': now,
          'user_id': userId,
        });

        final payments = await txn.rawQuery(
          '''
          SELECT SUM(amount) as total
          FROM ${DbTables.layawayPayments}
          WHERE sale_id = ?
        ''',
          [saleId],
        );
        final totalPaid =
            (payments.first['total'] as num?)?.toDouble() ?? 0.0;
        final totalDue = (sale['total'] as num?)?.toDouble() ?? 0.0;
        final pending = totalDue - totalPaid;

        await txn.update(
          DbTables.sales,
          {'paid_amount': totalPaid, 'updated_at_ms': now},
          where: 'id = ?',
          whereArgs: [saleId],
        );

        // Estado legible para tickets: PENDIENTE/PAGADO
        var status = pending > 0 ? 'PENDIENTE' : 'PAGADO';

        final sessionRows = await txn.query(
          DbTables.cashSessions,
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [resolvedSessionId],
          limit: 1,
        );
        final statusSession = sessionRows.isNotEmpty
            ? (sessionRows.first['status'] as String?) ?? ''
            : '';
        if (statusSession != 'OPEN') {
          throw BusinessRuleException(
            code: 'layaway_session_closed',
            messageUser: 'La sesión de caja no está abierta.',
            messageDev: 'Cash session not open for layaway payment saleId=$saleId',
          );
        }

        await txn.insert(DbTables.cashMovements, {
          'session_id': resolvedSessionId,
          'type': 'IN',
          'amount': amount,
          'note': note,
          'created_at_ms': now,
          'reason': 'Abono apartado #${sale['local_code'] ?? saleId}',
          'user_id': userId ?? 1,
        });

        if (pending <= 0) {
          await _finalizeLayaway(
            txn: txn,
            saleId: saleId,
            saleCode: (sale['local_code'] as String?) ?? saleId.toString(),
            totalPaid: totalPaid,
          );
          status = 'PAGADO';
        }

        return LayawayPaymentResult(
          paymentId: paymentId,
          totalPaid: totalPaid,
          pendingAmount: pending > 0 ? pending : 0,
          status: status,
        );
      });
    }, stage: 'layaway_register_payment');
  }

  static Future<void> _finalizeLayaway({
    required DatabaseExecutor txn,
    required int saleId,
    required String saleCode,
    required double totalPaid,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final items = await txn.query(
      DbTables.saleItems,
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );

    for (final item in items) {
      final productId = item['product_id'] as int?;
      if (productId == null) continue;
      final qtyValue = item['qty'];
      final qty = qtyValue is num
          ? qtyValue.toDouble()
          : double.tryParse(qtyValue.toString()) ?? 0.0;
      if (qty <= 0) continue;

      final productRows = await txn.query(
        DbTables.products,
        columns: ['stock', 'reserved_stock', 'name', 'code'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw BusinessRuleException(
          code: 'product_not_found',
          messageUser: 'No se encontrÃ³ un producto del apartado.',
          messageDev:
              'Product not found while finalizing layaway. productId=$productId',
        );
      }

      final currentStock =
          (productRows.first['stock'] as num?)?.toDouble() ?? 0.0;
      final newStock = currentStock - qty;
      if (newStock < 0) {
        final code =
            (productRows.first['code'] as String?)?.trim() ?? 'N/A';
        final name =
            (productRows.first['name'] as String?)?.trim() ?? 'Producto';
        throw BusinessRuleException(
          code: 'stock_negative',
          messageUser:
              'Stock insuficiente para "$name" ($code). Ajusta el inventario.',
          messageDev:
              'Stock would go negative while finalizing layaway: productId=$productId code=$code name="$name" current=$currentStock qty=$qty',
        );
      }

      await txn.rawUpdate(
        '''
        UPDATE ${DbTables.products}
        SET stock = stock - ?,
            reserved_stock = CASE
              WHEN reserved_stock - ? < 0 THEN 0
              ELSE reserved_stock - ?
            END
        WHERE id = ?
      ''',
        [qty, qty, qty, productId],
      );

      await txn.insert(DbTables.stockMovements, {
        'product_id': productId,
        'type': 'SALE',
        'quantity': -qty,
        'note': 'Apartado liquidado #$saleCode',
        'created_at_ms': now,
      });
    }

    await txn.update(
      DbTables.sales,
      {'status': 'completed', 'paid_amount': totalPaid, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  static Future<List<Map<String, dynamic>>> listLayawaySales() async {
    final db = await AppDb.database;

    final result = await db.rawQuery(
      '''
      SELECT s.*,
             COALESCE(SUM(lp.amount), 0) as amount_paid,
             (s.total - COALESCE(SUM(lp.amount), 0)) as amount_pending,
             CASE
               WHEN (s.total - COALESCE(SUM(lp.amount), 0)) <= 0 THEN 'PAID'
               ELSE 'PENDING'
             END as layaway_status
      FROM ${DbTables.sales} s
      LEFT JOIN ${DbTables.layawayPayments} lp ON s.id = lp.sale_id
      WHERE s.payment_method = 'layaway'
      GROUP BY s.id
      ORDER BY s.created_at_ms DESC
    ''',
    );

    return result;
  }
}
