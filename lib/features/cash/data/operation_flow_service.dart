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
// Problemas encontrados:
// - Riesgo de inconsistencias si se cierra caja con turnos abiertos.
// - Posibilidad de discrepancia UI/DB si faltan validaciones de estado al cerrar.
// - Necesidad de bloquear operación ante turno anterior sin cerrar.
// Plan de corrección:
// - Separar CAJA diaria (`cashbox_daily`) de TURNO (`cash_sessions`).
// - Forzar validación post-login mediante "Iniciar operación".
// - Endurecer validaciones transaccionales en apertura/cierre.
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
  // - Si el turno abierto excede 48 horas, debe hacer el corte antes de operar.
  bool get canOperate => hasUserShiftOpen && !hasStaleShift;
}

class OperationFlowService {
  OperationFlowService._();

  // Regla: un turno puede permanecer abierto hasta 48 horas.
  // Solo cuando excede ese tiempo se fuerza a hacer el corte antes de operar.
  static const Duration maxShiftOpenDuration = Duration(hours: 48);
  static final int _maxShiftOpenMs = maxShiftOpenDuration.inMilliseconds;

  static String businessDateOf([DateTime? date]) {
    return DateFormat('yyyy-MM-dd').format((date ?? DateTime.now()).toLocal());
  }

  static bool _isShiftOverMaxAge(CashSessionModel shift, int nowMs) {
    final diff = nowMs - shift.openedAtMs;
    if (diff <= 0) return false;
    return diff > _maxShiftOpenMs;
  }

  static Future<OperationGateState> loadGateState() async {
    final today = businessDateOf();
    final userId = await SessionManager.userId();

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final cashbox = await getDailyCashbox(today);
    final userShift = await CashRepository.getOpenSession(userId: userId);
    final stale = (userShift != null && _isShiftOverMaxAge(userShift, nowMs))
        ? userShift
        : null;

    return OperationGateState(
      businessDate: today,
      cashboxToday: cashbox,
      userOpenShift: userShift,
      staleOpenShift: stale,
    );
  }

  static Future<List<CashSessionModel>> listOpenShiftsForDailyCashbox({
    required int cashboxDailyId,
    required String businessDate,
  }) async {
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.cashSessions,
      where: '''
        status = 'OPEN'
        AND closed_at_ms IS NULL
        AND (cashbox_daily_id = ? OR (cashbox_daily_id IS NULL AND business_date = ?))
      ''',
      whereArgs: [cashboxDailyId, businessDate],
      orderBy: 'opened_at_ms ASC',
    );
    return rows.map(CashSessionModel.fromMap).toList(growable: false);
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

  static Future<CashboxDailyModel?> getDailyCashboxById(int? id) async {
    if (id == null) return null;
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.cashboxDaily,
      where: 'id = ?',
      whereArgs: [id],
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
      // Si ya existe una caja abierta para hoy, normalmente se devuelve tal cual.
      // Pero si aún no hay turnos/sesiones para esta caja, permitir ajustar
      // el fondo inicial (caso típico: caja creada en 0 por migración/flujo previo).
      if ((openingAmount - existing.initialAmount).abs() > 1e-9) {
        final countRows = await db.rawQuery(
          '''
          SELECT COUNT(*) AS total
          FROM ${DbTables.cashSessions}
          WHERE (cashbox_daily_id = ? OR (cashbox_daily_id IS NULL AND business_date = ?))
            AND business_date = ?
          ''',
          [existing.id, businessDate, businessDate],
        );
        final total = (countRows.first['total'] as int?) ?? 0;

        if (total == 0) {
          final previousNote = (existing.note ?? '').trim();
          final extraNote = (note ?? '').trim();
          final newNote = [
            if (previousNote.isNotEmpty) previousNote,
            if (extraNote.isNotEmpty) extraNote,
            'Ajuste fondo inicial: ${existing.initialAmount} -> $openingAmount (${DateTime.now().toLocal()})',
          ].join('\n');

          final updated = await db.update(
            DbTables.cashboxDaily,
            {
              'initial_amount': openingAmount,
              'current_amount': openingAmount,
              'opened_by_user_id': userId,
              'note': newNote,
            },
            where: 'id = ? AND status = ?',
            whereArgs: [existing.id, 'OPEN'],
          );

          if (updated == 1) {
            final row = await db.query(
              DbTables.cashboxDaily,
              where: 'id = ?',
              whereArgs: [existing.id],
              limit: 1,
            );
            if (row.isNotEmpty) {
              return CashboxDailyModel.fromMap(row.first);
            }
          }
        }
      }

      return existing;
    }

    // Si la caja del día existe y está cerrada, permitir REABRIR la misma caja.
    // Nota: la tabla tiene UNIQUE(business_date), así que no podemos insertar otra fila.
    if (existing != null && existing.isClosed) {
      await db.transaction((txn) async {
        final openRows = await txn.query(
          DbTables.cashSessions,
          columns: ['id'],
          where:
              "status = 'OPEN' AND closed_at_ms IS NULL AND (cashbox_daily_id = ? OR (cashbox_daily_id IS NULL AND business_date = ?))",
          whereArgs: [existing.id, businessDate],
          limit: 1,
        );
        if (openRows.isNotEmpty) {
          throw Exception(
            'No se puede reabrir la caja mientras existan turnos abiertos.',
          );
        }

        final previousNote = (existing.note ?? '').trim();
        final newNote = [
          if (previousNote.isNotEmpty) previousNote,
          if ((note ?? '').trim().isNotEmpty) note!.trim(),
          'Reapertura: ${DateTime.now().toLocal()}',
        ].join('\n');

        final updated = await txn.update(
          DbTables.cashboxDaily,
          {
            'opened_at_ms': now,
            'opened_by_user_id': userId,
            'initial_amount': openingAmount,
            'current_amount': openingAmount,
            'status': 'OPEN',
            'closed_at_ms': null,
            'closed_by_user_id': null,
            'note': newNote,
          },
          where: 'id = ? AND status = ?',
          whereArgs: [existing.id, 'CLOSED'],
        );
        if (updated != 1) {
          throw Exception(
            'No fue posible reabrir la caja diaria. Intenta nuevamente.',
          );
        }
      });

      final row = await db.query(
        DbTables.cashboxDaily,
        where: 'business_date = ?',
        whereArgs: [businessDate],
        limit: 1,
      );
      return CashboxDailyModel.fromMap(row.first);
    }

    final id = await db.insert(DbTables.cashboxDaily, {
      'business_date': businessDate,
      'opened_at_ms': now,
      'opened_by_user_id': userId,
      'initial_amount': openingAmount,
      'current_amount': openingAmount,
      'status': 'OPEN',
      'note': note,
    }, conflictAlgorithm: ConflictAlgorithm.abort);

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

    await db.transaction((txn) async {
      final openRows = await txn.query(
        DbTables.cashSessions,
        columns: ['id', 'opened_by_user_id', 'user_name', 'business_date'],
        where: '''
          status = 'OPEN'
          AND closed_at_ms IS NULL
          AND (cashbox_daily_id = ? OR (cashbox_daily_id IS NULL AND business_date = ?))
        ''',
        whereArgs: [cashbox.id, today],
        orderBy: 'opened_at_ms ASC',
      );

      if (openRows.isNotEmpty) {
        final details = openRows
            .map(
              (row) =>
                  '#${row['id']} (${row['user_name'] ?? 'cajero'} / user ${row['opened_by_user_id']})',
            )
            .join(', ');
        throw Exception(
          'No se puede cerrar caja: existen turnos abiertos ($details).',
        );
      }

      final updated = await txn.update(
        DbTables.cashboxDaily,
        {
          'status': 'CLOSED',
          'closed_at_ms': DateTime.now().millisecondsSinceEpoch,
          'closed_by_user_id': userId,
          'note': note,
        },
        where: 'id = ? AND status = ?',
        whereArgs: [cashbox.id, 'OPEN'],
      );

      if (updated != 1) {
        throw Exception(
          'No fue posible cerrar la caja diaria. Intenta nuevamente.',
        );
      }
    });
  }

  static Future<CashSessionModel> openShiftForCurrentUser({
    double openingAmount = 0,
  }) async {
    final userId = await SessionManager.userId() ?? 1;
    final userName =
        await SessionManager.displayName() ??
        await SessionManager.username() ??
        'Usuario';
    final businessDate = businessDateOf();

    final cashbox = await getOpenDailyCashboxToday();
    if (cashbox == null) {
      throw Exception('No hay caja abierta para hoy.');
    }

    final db = await AppDb.database;
    int? id;
    await db.transaction((txn) async {
      // Si el usuario abre el turno con 0, usar el fondo inicial de la caja diaria.
      // Importante: NO heredar montos del turno anterior (evita que parezca que
      // el monto "no se resetea" luego de cerrar y volver a abrir turno).
      var resolvedOpeningAmount = openingAmount;
      if (resolvedOpeningAmount.abs() < 1e-9) {
        resolvedOpeningAmount = cashbox.currentAmount;
      }

      final existingUserRows = await txn.query(
        DbTables.cashSessions,
        where: 'status = ? AND closed_at_ms IS NULL AND opened_by_user_id = ?',
        whereArgs: ['OPEN', userId],
        orderBy: 'opened_at_ms DESC',
        limit: 1,
      );
      if (existingUserRows.isNotEmpty) {
        id = existingUserRows.first['id'] as int?;
        return;
      }

      id = await txn.insert(DbTables.cashSessions, {
        'opened_by_user_id': userId,
        'user_name': userName,
        'opened_at_ms': DateTime.now().millisecondsSinceEpoch,
        'initial_amount': resolvedOpeningAmount,
        'cashbox_daily_id': cashbox.id,
        'business_date': businessDate,
        'requires_closure': 0,
        'status': 'OPEN',
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });

    if (id == null) {
      throw Exception('No se pudo abrir turno.');
    }

    final shift = await CashRepository.getSessionById(id!);
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
      expectedUserId: userId,
      expectedCashboxDailyId: openShift.cashboxDailyId,
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
