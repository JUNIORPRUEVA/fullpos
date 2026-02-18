import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/session/session_manager.dart';
import 'cash_repository.dart';
import 'cash_session_model.dart';
import 'cash_summary_model.dart';
import 'cashbox_daily_model.dart';

// Flujo actual detectado:
// - `cash_sessions` se usaba como una sola "caja/turno" por usuario.
// - Ventas dependían de la sesión abierta del usuario (overlay en Sales),
//   sin una entidad diaria separada para la caja física.
// Cambios requeridos:
// - Separar CAJA diaria (`cashbox_daily`) de TURNO (`cash_sessions`).
// - Forzar validación post-login mediante "Iniciar operación".
// Compatibilidad y migración:
// - Se mantiene `cash_sessions` y reportes existentes; se añaden columnas
//   `business_date`/`cashbox_daily_id` con backfill gradual.

class OperationGateState {
  final String businessDate;
  final CashboxDailyModel? cashboxToday;
  final CashSessionModel? userOpenShift;
  final CashSessionModel? staleOpenShift;

  const OperationGateState({
    required this.businessDate,
    required this.cashboxToday,
    required this.userOpenShift,
    required this.staleOpenShift,
  });

  bool get hasCashboxTodayOpen => cashboxToday?.isOpen == true;
  bool get hasUserShiftOpen => userOpenShift?.isOpen == true;
  bool get hasStaleShift => staleOpenShift != null;
  // Regla operativa:
  // - Puede operar si tiene turno abierto vigente.
  // - Si el turno abierto es pendiente de días anteriores, debe cerrarlo primero.
  bool get canOperate => hasUserShiftOpen && !hasStaleShift;
}

class OperationFlowService {
  OperationFlowService._();

  static String businessDateOf([DateTime? date]) {
    return DateFormat('yyyy-MM-dd').format((date ?? DateTime.now()).toLocal());
  }

  static Future<OperationGateState> loadGateState() async {
    final today = businessDateOf();
    final userId = await SessionManager.userId();

    final cashbox = await getDailyCashbox(today);
    final userShift = await CashRepository.getOpenSession(userId: userId);
    final stale = await _getOpenShiftBeforeDate(userId: userId, businessDate: today);

    return OperationGateState(
      businessDate: today,
      cashboxToday: cashbox,
      userOpenShift: userShift,
      staleOpenShift: stale,
    );
  }

  static Future<CashboxDailyModel?> getDailyCashbox(String businessDate) async {
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.cashboxDaily,
      where: 'business_date = ?',
      whereArgs: [businessDate],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CashboxDailyModel.fromMap(rows.first);
  }

  static Future<CashboxDailyModel?> getOpenDailyCashboxToday() async {
    final cashbox = await getDailyCashbox(businessDateOf());
    if (cashbox == null || !cashbox.isOpen) return null;
    return cashbox;
  }

  static Future<CashboxDailyModel> openDailyCashboxToday({
    required double openingAmount,
    String? note,
  }) async {
    final db = await AppDb.database;
    final userId = await SessionManager.userId() ?? 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final businessDate = businessDateOf();

    final existing = await getDailyCashbox(businessDate);
    if (existing != null && existing.isOpen) {
      return existing;
    }
    if (existing != null && existing.isClosed) {
      throw Exception('La caja de hoy ya fue cerrada y no puede reabrirse automáticamente.');
    }

    final id = await db.insert(
      DbTables.cashboxDaily,
      {
        'business_date': businessDate,
        'opened_at_ms': now,
        'opened_by_user_id': userId,
        'initial_amount': openingAmount,
        'status': 'OPEN',
        'note': note,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    final row = await db.query(
      DbTables.cashboxDaily,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return CashboxDailyModel.fromMap(row.first);
  }

  static Future<void> closeDailyCashboxToday({String? note}) async {
    final db = await AppDb.database;
    final today = businessDateOf();
    final userId = await SessionManager.userId() ?? 1;

    final cashbox = await getDailyCashbox(today);
    if (cashbox == null || !cashbox.isOpen) {
      throw Exception('No hay caja diaria abierta para hoy.');
    }

    final openShiftCountRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DbTables.cashSessions}
      WHERE status = 'OPEN'
        AND (
          cashbox_daily_id = ?
          OR (cashbox_daily_id IS NULL AND business_date = ?)
        )
      ''',
      [cashbox.id, today],
    );
    final openShiftCount = (openShiftCountRows.first['total'] as int?) ?? 0;
    if (openShiftCount > 0) {
      throw Exception('No se puede cerrar caja: existen turnos abiertos.');
    }

    await db.update(
      DbTables.cashboxDaily,
      {
        'status': 'CLOSED',
        'closed_at_ms': DateTime.now().millisecondsSinceEpoch,
        'closed_by_user_id': userId,
        'note': note,
      },
      where: 'id = ?',
      whereArgs: [cashbox.id],
    );
  }

  static Future<CashSessionModel?> _getOpenShiftBeforeDate({
    required int? userId,
    required String businessDate,
  }) async {
    if (userId == null) return null;
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.cashSessions,
      where: "status = 'OPEN' AND opened_by_user_id = ? AND business_date < ?",
      whereArgs: [userId, businessDate],
      orderBy: 'opened_at_ms ASC',
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return CashSessionModel.fromMap(rows.first);
  }

  static Future<CashSessionModel> openShiftForCurrentUser({
    double openingAmount = 0,
  }) async {
    final userId = await SessionManager.userId() ?? 1;
    final userName =
        await SessionManager.displayName() ?? await SessionManager.username() ?? 'Usuario';
    final businessDate = businessDateOf();

    final stale = await _getOpenShiftBeforeDate(userId: userId, businessDate: businessDate);
    if (stale != null) {
      throw Exception('Existe un turno anterior sin cerrar. Debe cerrarlo para continuar.');
    }

    final existingUserShift = await CashRepository.getOpenSession(userId: userId);
    if (existingUserShift != null) {
      return existingUserShift;
    }

    final cashbox = await getOpenDailyCashboxToday();
    if (cashbox == null) {
      throw Exception('No hay caja abierta para hoy.');
    }

    final db = await AppDb.database;
    final anyOpenRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DbTables.cashSessions}
      WHERE status = 'OPEN'
        AND (
          cashbox_daily_id = ?
          OR (cashbox_daily_id IS NULL AND business_date = ?)
        )
      ''',
      [cashbox.id, businessDate],
    );
    final anyOpen = (anyOpenRows.first['total'] as int?) ?? 0;
    if (anyOpen > 0) {
      throw Exception('Ya existe un turno abierto en esta caja.');
    }

    final id = await CashRepository.openSession(
      userId: userId,
      userName: userName,
      openingAmount: openingAmount,
      cashboxDailyId: cashbox.id,
      businessDate: businessDate,
      requiresClosure: false,
    );

    final shift = await CashRepository.getSessionById(id);
    if (shift == null) throw Exception('No se pudo abrir turno.');
    return shift;
  }

  static Future<void> closeOpenShiftForCurrentUser({
    required double closingAmount,
    required String note,
  }) async {
    final userId = await SessionManager.userId();
    final openShift = await CashRepository.getOpenSession(userId: userId);
    if (openShift == null || openShift.id == null) {
      return;
    }

    final summary = await CashRepository.buildSummary(sessionId: openShift.id!);
    await CashRepository.closeSession(
      sessionId: openShift.id!,
      closingAmount: closingAmount,
      note: note,
      summary: summary,
    );
  }

  static Future<bool> hasOpenShiftForCurrentUser() async {
    final shift = await CashRepository.getOpenSession();
    return shift != null;
  }

  static Future<CashSummaryModel?> buildCurrentShiftSummary() async {
    final shift = await CashRepository.getOpenSession();
    if (shift?.id == null) return null;
    return CashRepository.buildSummary(sessionId: shift!.id!);
  }
}
