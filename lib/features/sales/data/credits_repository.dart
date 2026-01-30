import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/db_hardening/db_hardening.dart';
import 'sales_model.dart';

class CreditPaymentResult {
  final int paymentId;
  final double totalPaid;
  final double pendingAmount;
  final double totalDue;

  CreditPaymentResult({
    required this.paymentId,
    required this.totalPaid,
    required this.pendingAmount,
    required this.totalDue,
  });
}

class CreditsRepository {
  CreditsRepository._();

  /// Registra un pago de crédito
  static Future<CreditPaymentResult> registerCreditPayment({
    required int saleId,
    required int clientId,
    required double amount,
    required String method,
    String? note,
    int? userId,
    int? sessionId,
  }) async {
    return await DbHardening.instance.runDbSafe<CreditPaymentResult>(() async {
      final db = await AppDb.database;

      return await db.transaction((txn) async {
        final now = DateTime.now().millisecondsSinceEpoch;

      // Obtener venta para comparar totales y completar cliente si falta
      final sale = await txn.query(
        DbTables.sales,
        where: 'id = ?',
        whereArgs: [saleId],
      );

      final resolvedClientId = clientId != 0
          ? clientId
          : (sale.isNotEmpty ? (sale.first['customer_id'] as int? ?? 0) : 0);
        final resolvedSessionId = sessionId ??
          (sale.isNotEmpty
            ? ((sale.first['cash_session_id'] as int?) ??
              (sale.first['session_id'] as int?))
            : null);
        final saleCode = sale.isNotEmpty
          ? (sale.first['local_code'] as String?) ?? 'CR-$saleId'
          : 'CR-$saleId';

      // Insertar pago
        final paymentId = await txn.insert(DbTables.creditPayments, {
          'sale_id': saleId,
          'client_id': resolvedClientId,
          'amount': amount,
          'method': method,
          'note': note,
          'created_at_ms': now,
          'user_id': userId,
        });

      // Verificar si el crédito está completamente pagado
        final payments = await txn.rawQuery(
        '''SELECT SUM(amount) as total FROM ${DbTables.creditPayments} 
           WHERE sale_id = ?''',
        [saleId],
      );

        final totalPaid = (payments.first['total'] as num?)?.toDouble() ?? 0.0;
        double totalDue = 0.0;

      if (sale.isNotEmpty) {
          final saleTotal = (sale.first['total'] as num).toDouble();
          final interestRate =
            (sale.first['credit_interest_rate'] as num?)?.toDouble() ?? 0.0;
          totalDue = saleTotal + (saleTotal * interestRate / 100.0);

        // Actualizar pagado acumulado
          await txn.update(
            DbTables.sales,
            {'paid_amount': totalPaid, 'updated_at_ms': now},
            where: 'id = ?',
            whereArgs: [saleId],
          );

        // Si pagó todo, marcar como PAID
          if (totalPaid >= totalDue) {
            await txn.update(
              DbTables.sales,
              {'status': 'PAID', 'updated_at_ms': now},
              where: 'id = ?',
              whereArgs: [saleId],
            );
          }
        } else {
          totalDue = totalPaid;
        }

        final pending = (totalDue - totalPaid).clamp(0.0, double.infinity);

        if (resolvedSessionId == null) {
          throw Exception(
            'No hay caja abierta para registrar abono de crédito.',
          );
        }

        final sessionRows = await txn.query(
          DbTables.cashSessions,
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [resolvedSessionId],
          limit: 1,
        );
        final status = sessionRows.isNotEmpty
            ? (sessionRows.first['status'] as String?) ?? ''
            : '';
        if (status != 'OPEN') {
          throw Exception('La sesión de caja no está abierta.');
        }

        await txn.insert(DbTables.cashMovements, {
          'session_id': resolvedSessionId,
          'type': 'IN',
          'amount': amount,
          'note': note,
          'created_at_ms': now,
          'reason': 'Abono credito #$saleCode',
          'user_id': userId ?? 1,
        });

        return CreditPaymentResult(
          paymentId: paymentId,
          totalPaid: totalPaid,
          pendingAmount: pending,
          totalDue: totalDue,
        );
      });
    }, stage: 'credits/register_payment');
  }

  /// Obtiene todas las ventas a crédito
  static Future<List<Map<String, dynamic>>> listCreditSales({
    int? clientId,
    String? status,
  }) async {
    final db = await AppDb.database;

    String where = "s.payment_method = 'credit'";
    List<dynamic> args = [];

    if (clientId != null) {
      where += ' AND s.customer_id = ?';
      args.add(clientId);
    }

    if (status != null) {
      where += ' AND s.status = ?';
      args.add(status);
    }

    final result = await db.rawQuery(
      '''SELECT s.*, 
                COALESCE(SUM(cp.amount), 0) as amount_paid,
                (s.total + (s.total * COALESCE(s.credit_interest_rate, 0) / 100.0)) as total_due,
                ((s.total + (s.total * COALESCE(s.credit_interest_rate, 0) / 100.0)) - COALESCE(SUM(cp.amount), 0)) as amount_pending,
                CASE
                  WHEN ((s.total + (s.total * COALESCE(s.credit_interest_rate, 0) / 100.0)) - COALESCE(SUM(cp.amount), 0)) <= 0 THEN 'PAID'
                  ELSE 'PENDING'
                END as credit_status
         FROM ${DbTables.sales} s
         LEFT JOIN ${DbTables.creditPayments} cp ON s.id = cp.sale_id
         WHERE $where
         GROUP BY s.id
         ORDER BY s.created_at_ms DESC''',
      args,
    );

    return result;
  }

  /// Obtiene resumen de créditos por cliente
  static Future<List<Map<String, dynamic>>> getCreditSummaryByClient() async {
    final db = await AppDb.database;

    final result = await db.rawQuery(
      '''SELECT c.id, c.nombre, c.telefono,
                COUNT(DISTINCT s.id) as total_credits,
                SUM(s.total + (s.total * COALESCE(s.credit_interest_rate, 0) / 100.0)) as total_amount,
                COALESCE(SUM(cp.amount), 0) as total_paid,
                (SUM(s.total + (s.total * COALESCE(s.credit_interest_rate, 0) / 100.0)) - COALESCE(SUM(cp.amount), 0)) as total_pending
         FROM ${DbTables.clients} c
         LEFT JOIN ${DbTables.sales} s ON c.id = s.customer_id AND s.payment_method = 'credit'
         LEFT JOIN ${DbTables.creditPayments} cp ON s.id = cp.sale_id
         WHERE s.id IS NOT NULL
         GROUP BY c.id, c.nombre, c.telefono
         ORDER BY total_pending DESC''',
    );

    return result;
  }

  /// Obtiene los pagos de un crédito
  static Future<List<CreditPaymentModel>> getCreditPayments(int saleId) async {
    final db = await AppDb.database;

    final result = await db.query(
      DbTables.creditPayments,
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'created_at_ms DESC',
    );

    return result.map((map) => CreditPaymentModel.fromMap(map)).toList();
  }

  /// Obtiene el saldo pendiente de un crédito
  static Future<double> getCreditBalance(int saleId) async {
    final db = await AppDb.database;

    // Obtener total de venta
    final sale = await db.query(
      DbTables.sales,
      where: 'id = ?',
      whereArgs: [saleId],
      columns: ['total'],
    );

    if (sale.isEmpty) return 0.0;

    final saleTotal = (sale.first['total'] as num).toDouble();
    final interestRate =
        (sale.first['credit_interest_rate'] as num?)?.toDouble() ?? 0.0;
    final totalDue = saleTotal + (saleTotal * interestRate / 100.0);

    // Obtener total pagado
    final payments = await db.rawQuery(
      '''SELECT SUM(amount) as total FROM ${DbTables.creditPayments} 
         WHERE sale_id = ?''',
      [saleId],
    );

    final totalPaid = (payments.first['total'] as num?)?.toDouble() ?? 0.0;

    return (totalDue - totalPaid).clamp(0.0, double.infinity);
  }

  /// Obtiene el saldo total de crédito de un cliente
  static Future<double> getClientTotalCredit(int clientId) async {
    final db = await AppDb.database;

    final result = await db.rawQuery(
      '''SELECT SUM((s.total + (s.total * COALESCE(s.credit_interest_rate, 0) / 100.0)) - COALESCE(SUM(cp.amount), 0)) as total_pending
         FROM ${DbTables.sales} s
         LEFT JOIN ${DbTables.creditPayments} cp ON s.id = cp.sale_id
         WHERE s.customer_id = ? AND s.payment_method = 'credit'
         GROUP BY s.customer_id''',
      [clientId],
    );

    if (result.isEmpty) return 0.0;
    return (result.first['total_pending'] as num?)?.toDouble() ?? 0.0;
  }
}
