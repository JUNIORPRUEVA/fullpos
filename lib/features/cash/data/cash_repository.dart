import 'package:sqflite/sqflite.dart';
import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/session/session_manager.dart';
import 'cash_session_model.dart';
import 'cash_movement_model.dart';
import 'cash_summary_model.dart';

/// Repositorio completo de Caja
class CashRepository {
  CashRepository._();

  // ===================== SESIONES DE CAJA =====================

  static Future<int?> _resolveUserId({int? userId}) async {
    if (userId != null) return userId;
    return await SessionManager.userId();
  }

  /// Obtener sesión abierta (global o por usuario)
  static Future<CashSessionModel?> getOpenSession({int? userId}) async {
    return DbHardening.instance.runDbSafe<CashSessionModel?>(() async {
      final db = await AppDb.database;

      String where = 'status = ?';
      List<dynamic> args = ['OPEN'];

      final resolvedUserId = await _resolveUserId(userId: userId);
      if (resolvedUserId != null) {
        where += ' AND opened_by_user_id = ?';
        args.add(resolvedUserId);
      }

      final result = await db.query(
        DbTables.cashSessions,
        where: where,
        whereArgs: args,
        orderBy: 'opened_at_ms DESC',
        limit: 1,
      );

      if (result.isEmpty) return null;
      return CashSessionModel.fromMap(result.first);
    }, stage: 'cash_get_open_session');
  }

  /// Abrir nueva sesión de caja
  static Future<int> openSession({
    required int userId,
    required String userName,
    required double openingAmount,
  }) {
    // FULLPOS DB HARDENING: proteger la apertura de sesiones ante errores SQLite.
    return DbHardening.instance.runDbSafe<int>(() async {
      final db = await AppDb.database;

      // Verificar que no haya otra sesión abierta
      final existing = await getOpenSession(userId: userId);
      if (existing != null) {
        throw Exception('Ya existe una caja abierta. Ciérrela primero.');
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      final session = CashSessionModel(
        userId: userId,
        userName: userName,
        openedAtMs: now,
        openingAmount: openingAmount,
        status: CashSessionStatus.open,
      );

      final id = await db.insert(
        DbTables.cashSessions,
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return id;
    }, stage: 'cash_open_session');
  }

  /// Cerrar sesión de caja con transacción
  static Future<void> closeSession({
    required int sessionId,
    required double closingAmount,
    required String note,
    required CashSummaryModel summary,
  }) {
    // FULLPOS DB HARDENING: asegurar el cierre de caja antes de comprometer cambios.
    return DbHardening.instance.runDbSafe<void>(() async {
      final db = await AppDb.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      final difference = summary.calculateDifference(closingAmount);

      await db.transaction((txn) async {
        await txn.update(
          DbTables.cashSessions,
          {
            'closed_at_ms': now,
            'closing_amount': closingAmount,
            'expected_cash': summary.expectedCash,
            'difference': difference,
            'note': note,
            'status': CashSessionStatus.closed,
          },
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      });
    }, stage: 'cash_close_session');
  }

  /// Obtener sesión por ID
  static Future<CashSessionModel?> getSessionById(int id) async {
    return DbHardening.instance.runDbSafe<CashSessionModel?>(() async {
      final db = await AppDb.database;

      final result = await db.query(
        DbTables.cashSessions,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return CashSessionModel.fromMap(result.first);
    }, stage: 'cash_get_session_by_id');
  }

  /// Listar historial de sesiones cerradas
  static Future<List<CashSessionModel>> listClosedSessions({
    int? userId,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    return DbHardening.instance.runDbSafe<List<CashSessionModel>>(() async {
      final db = await AppDb.database;

      var where = '(status = ? OR closed_at_ms IS NOT NULL)';
      final args = <dynamic>['CLOSED'];

      final resolvedUserId = await _resolveUserId(userId: userId);
      if (resolvedUserId != null) {
        where += ' AND opened_by_user_id = ?';
        args.add(resolvedUserId);
      }

      if (from != null) {
        where += ' AND closed_at_ms >= ?';
        args.add(from.millisecondsSinceEpoch);
      }
      if (to != null) {
        where += ' AND closed_at_ms < ?';
        args.add(to.add(const Duration(days: 1)).millisecondsSinceEpoch);
      }

      final result = await db.query(
        DbTables.cashSessions,
        where: where,
        whereArgs: args,
        orderBy: 'closed_at_ms DESC',
        limit: limit,
        offset: offset,
      );

      return result.map((map) => CashSessionModel.fromMap(map)).toList();
    }, stage: 'cash_list_closed_sessions');
  }

  // ===================== MOVIMIENTOS DE CAJA =====================

  /// Agregar movimiento de caja (entrada/salida)
  static Future<int> addMovement({
    required int sessionId,
    required String type, // 'IN' o 'OUT'
    required double amount,
    required String reason,
    required int userId,
  }) {
    // FULLPOS DB HARDENING: reforzar el registro de movimientos críticos.
    return DbHardening.instance.runDbSafe<int>(() async {
      final db = await AppDb.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Validar que el tipo sea correcto
      if (type != CashMovementType.income && type != CashMovementType.outcome) {
        throw Exception('Tipo de movimiento inválido: $type');
      }

      // Validar que la sesión esté abierta
      final session = await getSessionById(sessionId);
      if (session == null || !session.isOpen) {
        throw Exception('La sesión de caja no está abierta.');
      }

      final movement = CashMovementModel(
        sessionId: sessionId,
        type: type,
        amount: amount,
        reason: reason,
        createdAtMs: now,
        userId: userId,
      );

      final id = await db.insert(
        DbTables.cashMovements,
        movement.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return id;
    }, stage: 'cash_add_movement');
  }

  /// Listar movimientos de una sesión
  static Future<List<CashMovementModel>> listMovements({
    required int sessionId,
  }) {
    return DbHardening.instance.runDbSafe<List<CashMovementModel>>(() async {
      final db = await AppDb.database;

      final result = await db.query(
        DbTables.cashMovements,
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at_ms ASC',
      );

      return result.map((map) => CashMovementModel.fromMap(map)).toList();
    }, stage: 'cash_list_movements');
  }

  /// Listar movimientos por rango de fechas (opcionalmente por usuario)
  static Future<List<CashMovementModel>> listMovementsRange({
    int? userId,
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    return DbHardening.instance.runDbSafe<List<CashMovementModel>>(() async {
      final db = await AppDb.database;

      var where = '1=1';
      final args = <dynamic>[];

      final resolvedUserId = await _resolveUserId(userId: userId);
      if (resolvedUserId != null) {
        where += ' AND user_id = ?';
        args.add(resolvedUserId);
      }
      if (from != null) {
        where += ' AND created_at_ms >= ?';
        args.add(from.millisecondsSinceEpoch);
      }
      if (to != null) {
        where += ' AND created_at_ms < ?';
        args.add(to.add(const Duration(days: 1)).millisecondsSinceEpoch);
      }

      final result = await db.query(
        DbTables.cashMovements,
        where: where,
        whereArgs: args,
        orderBy: 'created_at_ms DESC',
        limit: limit,
      );

      return result.map((map) => CashMovementModel.fromMap(map)).toList();
    }, stage: 'cash_list_movements_range');
  }

  // ===================== RESUMEN Y CÁLCULOS =====================

  /// Construir resumen completo de la sesión
  static Future<CashSummaryModel> buildSummary({required int sessionId}) {
    return DbHardening.instance.runDbSafe<CashSummaryModel>(
      () => _buildSummaryUnsafe(sessionId),
      stage: 'cash_build_summary',
    );
  }

  static Future<CashSummaryModel> _buildSummaryUnsafe(int sessionId) async {
    final db = await AppDb.database;

    // Obtener sesión para el monto de apertura
    final session = await getSessionById(sessionId);
    if (session == null) {
      throw Exception('Sesión no encontrada: $sessionId');
    }

    final openingAmount = session.openingAmount;

    // Calcular movimientos manuales IN (incluye abonos de crédito y apartado)
    final inResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) as total
      FROM ${DbTables.cashMovements}
      WHERE session_id = ? AND type = 'IN'
    ''',
      [sessionId],
    );
    final cashInManual = (inResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Identificar abonos de crédito dentro de los IN
    final creditAbonoResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) as total
      FROM ${DbTables.cashMovements}
      WHERE session_id = ?
        AND type = 'IN'
        AND (
          LOWER(reason) LIKE '%abono credito%'
          OR LOWER(reason) LIKE '%abono cr%c%dito%'
        )
    ''',
      [sessionId],
    );
    final creditAbonos =
        (creditAbonoResult.first['total'] as num?)?.toDouble() ?? 0.0;

    final layawayAbonoResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) as total
      FROM ${DbTables.cashMovements}
      WHERE session_id = ? AND type = 'IN' AND LOWER(reason) LIKE '%abono apartado%'
    ''',
      [sessionId],
    );
    final layawayAbonos =
        (layawayAbonoResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Calcular movimientos manuales OUT
    final outResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) as total
      FROM ${DbTables.cashMovements}
      WHERE session_id = ? AND type = 'OUT'
    ''',
      [sessionId],
    );
    final cashOutManual = (outResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Ventas en efectivo (usando cash_session_id o session_id)
    final cashSalesResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(paid_amount), 0) as total
      FROM ${DbTables.sales}
      WHERE (cash_session_id = ? OR session_id = ?)
        AND kind = 'invoice'
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
        AND payment_method = 'cash'
        AND deleted_at_ms IS NULL
    ''',
      [sessionId, sessionId],
    );
    final salesCashTotal =
        (cashSalesResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Ventas con tarjeta
    final cardSalesResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total), 0) as total
      FROM ${DbTables.sales}
      WHERE (cash_session_id = ? OR session_id = ?)
        AND kind = 'invoice'
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
        AND payment_method = 'card'
        AND deleted_at_ms IS NULL
    ''',
      [sessionId, sessionId],
    );
    final salesCardTotal =
        (cardSalesResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Ventas por transferencia
    final transferSalesResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total), 0) as total
      FROM ${DbTables.sales}
      WHERE (cash_session_id = ? OR session_id = ?)
        AND kind = 'invoice'
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
        AND payment_method = 'transfer'
        AND deleted_at_ms IS NULL
    ''',
      [sessionId, sessionId],
    );
    final salesTransferTotal =
        (transferSalesResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Ventas a crédito
    final creditSalesResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total), 0) as total
      FROM ${DbTables.sales}
      WHERE (cash_session_id = ? OR session_id = ?)
        AND kind = 'invoice'
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
        AND payment_method = 'credit'
        AND deleted_at_ms IS NULL
    ''',
      [sessionId, sessionId],
    );
    final salesCreditTotal =
        (creditSalesResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Total de tickets
    final ticketsResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM ${DbTables.sales}
      WHERE (cash_session_id = ? OR session_id = ?)
        AND kind = 'invoice'
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
        AND deleted_at_ms IS NULL
    ''',
      [sessionId, sessionId],
    );
    final totalTickets = (ticketsResult.first['count'] as int?) ?? 0;

    // Devoluciones en efectivo
    // Importante: las devoluciones se guardan con total NEGATIVO (para hacer offset contable).
    // Para caja necesitamos el monto ABS (efectivo que sale).
    final refundsResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(ABS(total)), 0) as total
      FROM ${DbTables.sales}
      WHERE (cash_session_id = ? OR session_id = ?)
        AND kind = 'return'
        AND deleted_at_ms IS NULL
    ''',
      [sessionId, sessionId],
    );
    final refundsCash =
        (refundsResult.first['total'] as num?)?.toDouble() ?? 0.0;

    // Total de devoluciones (cantidad)
    final refundsCountResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM ${DbTables.sales}
      WHERE (cash_session_id = ? OR session_id = ?)
        AND kind = 'return'
        AND deleted_at_ms IS NULL
    ''',
      [sessionId, sessionId],
    );
    final totalRefunds = (refundsCountResult.first['count'] as int?) ?? 0;

    // Calcular efectivo esperado
    // expected = apertura + ventas efectivo + entradas - salidas - devoluciones efectivo
    // Nota: el cambio ya se resta del paid_amount en ventas efectivo
    final expectedCash =
        openingAmount +
        salesCashTotal +
        cashInManual -
        cashOutManual -
        refundsCash;

    return CashSummaryModel(
      openingAmount: openingAmount,
      cashInManual: cashInManual,
      cashOutManual: cashOutManual,
      creditAbonos: creditAbonos,
      layawayAbonos: layawayAbonos,
      salesCashTotal: salesCashTotal,
      salesCardTotal: salesCardTotal,
      salesTransferTotal: salesTransferTotal,
      salesCreditTotal: salesCreditTotal,
      refundsCash: refundsCash,
      expectedCash: expectedCash,
      totalTickets: totalTickets,
      totalRefunds: totalRefunds,
    );
  }

  // ===================== UTILIDADES =====================

  /// Lista devoluciones (ventas kind=return) de una sesión con nota y códigos
  static Future<List<Map<String, dynamic>>> listRefundsForSession(
    int sessionId,
  ) {
    return DbHardening.instance
        .runDbSafe<List<Map<String, dynamic>>>(() async {
      final db = await AppDb.database;

      return db.rawQuery(
        '''
      SELECT
        s.local_code AS return_code,
        s.total AS total,
        s.created_at_ms AS created_at_ms,
        (
          SELECT ri.description
          FROM ${DbTables.returnItems} ri
          WHERE ri.return_id = r.id
          ORDER BY ri.id ASC
          LIMIT 1
        ) AS first_product_name,
        (
          SELECT COUNT(*)
          FROM ${DbTables.returnItems} ri
          WHERE ri.return_id = r.id
        ) AS item_count,
        (
          SELECT GROUP_CONCAT(description, ', ')
          FROM (
            SELECT ri.description AS description
            FROM ${DbTables.returnItems} ri
            WHERE ri.return_id = r.id
            ORDER BY ri.id ASC
            LIMIT 3
          )
        ) AS products_preview,
        r.note AS note,
        os.local_code AS original_code,
        COALESCE(os.customer_name_snapshot, s.customer_name_snapshot) AS customer_name,
        COALESCE(os.customer_phone_snapshot, s.customer_phone_snapshot) AS customer_phone,
        COALESCE(os.customer_rnc_snapshot, s.customer_rnc_snapshot) AS customer_rnc,
        os.ncf_full AS original_ncf
      FROM ${DbTables.returns} r
      JOIN ${DbTables.sales} s ON r.return_sale_id = s.id
      LEFT JOIN ${DbTables.sales} os ON r.original_sale_id = os.id
      WHERE (s.cash_session_id = ? OR s.session_id = ?)
        AND s.kind = 'return'
        AND s.deleted_at_ms IS NULL
      ORDER BY s.created_at_ms DESC
        ''',
        [sessionId, sessionId],
      );
    }, stage: 'cash_list_refunds');
  }

  /// Verificar si hay caja abierta
  static Future<bool> hasOpenSession({int? userId}) async {
    final session = await getOpenSession(userId: userId);
    return session != null;
  }

  /// Obtener ID de la sesión abierta actual
  static Future<int?> getCurrentSessionId({int? userId}) async {
    final session = await getOpenSession(userId: userId);
    return session?.id;
  }

  /// Resumen por categoria para una sesion de caja.
  static Future<List<CategoryCashSummary>> listCategorySummaryForSession(
    int sessionId,
  ) async {
    return DbHardening.instance.runDbSafe<List<CategoryCashSummary>>(() async {
      final db = await AppDb.database;
      final rows = await db.rawQuery(
        '''
        SELECT
          category,
          COALESCE(SUM(sales_total), 0) as sales_total,
          COALESCE(SUM(refund_total), 0) as refund_total,
          COALESCE(SUM(items_sold), 0) as items_sold,
          COALESCE(SUM(items_refunded), 0) as items_refunded
        FROM (
          SELECT
            COALESCE(c.name, 'Sin categoria') as category,
            COALESCE(SUM(si.total_line), 0) as sales_total,
            0 as refund_total,
            COALESCE(SUM(si.qty), 0) as items_sold,
            0 as items_refunded
          FROM ${DbTables.saleItems} si
          INNER JOIN ${DbTables.sales} s ON si.sale_id = s.id
          LEFT JOIN ${DbTables.products} p
            ON (si.product_id = p.id)
            OR (
              si.product_id IS NULL
              AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
            )
          LEFT JOIN ${DbTables.categories} c ON p.category_id = c.id
          WHERE (s.cash_session_id = ? OR s.session_id = ?)
            AND s.kind IN ('invoice', 'sale')
            AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
            AND s.deleted_at_ms IS NULL
          GROUP BY category
          UNION ALL
          SELECT
            COALESCE(c.name, 'Sin categoria') as category,
            0 as sales_total,
            COALESCE(SUM(ri.total), 0) as refund_total,
            0 as items_sold,
            COALESCE(SUM(ri.qty), 0) as items_refunded
          FROM ${DbTables.returnItems} ri
          INNER JOIN ${DbTables.returns} r ON ri.return_id = r.id
          INNER JOIN ${DbTables.sales} s ON r.return_sale_id = s.id
          LEFT JOIN ${DbTables.saleItems} si ON ri.sale_item_id = si.id
          LEFT JOIN ${DbTables.products} p ON COALESCE(ri.product_id, si.product_id) = p.id
          LEFT JOIN ${DbTables.categories} c ON p.category_id = c.id
          WHERE (s.cash_session_id = ? OR s.session_id = ?)
            AND s.kind = 'return'
            AND s.deleted_at_ms IS NULL
          GROUP BY category
        ) t
        GROUP BY category
        ORDER BY sales_total DESC, refund_total DESC
        ''',
        [sessionId, sessionId, sessionId, sessionId],
      );

      return rows
          .map(
            (row) => CategoryCashSummary(
              category: row['category'] as String? ?? 'Sin categoria',
              salesTotal:
                  (row['sales_total'] as num?)?.toDouble() ?? 0.0,
              refundTotal:
                  (row['refund_total'] as num?)?.toDouble() ?? 0.0,
              itemsSold:
                  (row['items_sold'] as num?)?.toDouble() ?? 0.0,
              itemsRefunded:
                  (row['items_refunded'] as num?)?.toDouble() ?? 0.0,
            ),
          )
          .toList();
    }, stage: 'cash_category_summary');
  }

  /// Items reembolsados por categoria para una sesion de caja.
  static Future<List<RefundItemByCategory>> listRefundItemsByCategoryForSession(
    int sessionId,
  ) async {
    return DbHardening.instance.runDbSafe<List<RefundItemByCategory>>(() async {
      final db = await AppDb.database;
      final rows = await db.rawQuery(
        '''
        SELECT
          COALESCE(c.name, 'Sin categoria') as category,
          COALESCE(ri.description, si.product_name_snapshot, p.name, 'Item') as product_name,
          COALESCE(SUM(ri.qty), 0) as qty,
          COALESCE(SUM(ri.total), 0) as total
        FROM ${DbTables.returnItems} ri
        INNER JOIN ${DbTables.returns} r ON ri.return_id = r.id
        INNER JOIN ${DbTables.sales} s ON r.return_sale_id = s.id
        LEFT JOIN ${DbTables.saleItems} si ON ri.sale_item_id = si.id
        LEFT JOIN ${DbTables.products} p ON COALESCE(ri.product_id, si.product_id) = p.id
        LEFT JOIN ${DbTables.categories} c ON p.category_id = c.id
        WHERE (s.cash_session_id = ? OR s.session_id = ?)
          AND s.kind = 'return'
          AND s.deleted_at_ms IS NULL
        GROUP BY category, product_name
        ORDER BY category ASC, total DESC
        ''',
        [sessionId, sessionId],
      );

      return rows
          .map(
            (row) => RefundItemByCategory(
              category: row['category'] as String? ?? 'Sin categoria',
              productName: row['product_name'] as String? ?? 'Item',
              qty: (row['qty'] as num?)?.toDouble() ?? 0.0,
              total: (row['total'] as num?)?.toDouble() ?? 0.0,
            ),
          )
          .toList();
    }, stage: 'cash_category_refunds');
  }
}

class CategoryCashSummary {
  final String category;
  final double salesTotal;
  final double refundTotal;
  final double itemsSold;
  final double itemsRefunded;

  CategoryCashSummary({
    required this.category,
    required this.salesTotal,
    required this.refundTotal,
    required this.itemsSold,
    required this.itemsRefunded,
  });

  double get netTotal => salesTotal - refundTotal;
}

class RefundItemByCategory {
  final String category;
  final String productName;
  final double qty;
  final double total;

  RefundItemByCategory({
    required this.category,
    required this.productName,
    required this.qty,
    required this.total,
  });
}
