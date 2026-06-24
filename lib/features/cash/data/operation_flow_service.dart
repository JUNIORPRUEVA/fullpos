import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/session/session_manager.dart';
import 'cash_repository.dart';
import 'cash_session_model.dart';
import 'cash_summary_model.dart';
import 'cashbox_daily_model.dart';

class ActiveSession {
  final int userId;
  final int cashId;
  final int shiftId;
  final int openedAt;
  final String status;
  final String userName;
  final String businessDate;

  const ActiveSession({
    required this.userId,
    required this.cashId,
    required this.shiftId,
    required this.openedAt,
    required this.status,
    required this.userName,
    required this.businessDate,
  });

  bool get isOpen => status == CashSessionStatus.open;

  factory ActiveSession.fromModels({
    required CashboxDailyModel cashbox,
    required CashSessionModel shift,
  }) {
    final shiftId = shift.id;
    final cashId = cashbox.id;
    if (shiftId == null || cashId == null) {
      throw StateError('La sesión activa no tiene identificadores válidos.');
    }

    return ActiveSession(
      userId: shift.userId,
      cashId: cashId,
      shiftId: shiftId,
      openedAt: shift.openedAtMs,
      status: shift.status,
      userName: shift.userName,
      businessDate: cashbox.businessDate,
    );
  }
}

// Arquitectura actual:
// - La UI opera sobre una única `ActiveSession`.
// - `cashbox_daily` y `cash_sessions` se preservan como detalles internos
//   de persistencia para no romper ventas ni reportes existentes.
// - La apertura/cierre visible del sistema siempre ocurre como una sola sesión.

class OperationGateState {
  final String businessDate;
  final CashboxDailyModel? cashboxToday;
  final CashSessionModel? userOpenShift;
  final CashSessionModel? staleOpenShift;
  final ActiveSession? activeSession;

  const OperationGateState({
    required this.businessDate,
    required this.cashboxToday,
    required this.userOpenShift,
    required this.staleOpenShift,
    required this.activeSession,
  });

  bool get hasCashboxTodayOpen => cashboxToday?.isOpen == true;
  bool get hasUserShiftOpen => userOpenShift?.isOpen == true;
  bool get hasStaleShift => staleOpenShift != null;
  bool get canOperate => activeSession?.isOpen == true;
}

class OperationFlowService {
  OperationFlowService._();

  // Regla: un turno puede permanecer abierto hasta 48 horas.
  // Solo cuando excede ese tiempo se fuerza a hacer el corte antes de operar.
  static const Duration maxShiftOpenDuration = Duration(hours: 48);
  static final int _maxShiftOpenMs = maxShiftOpenDuration.inMilliseconds;

  static final DateFormat _businessDateFormat = DateFormat('yyyy-MM-dd');
  static ActiveSession? _pendingRestoredSessionNotice;

  static String businessDateOf([DateTime? date]) {
    return _businessDateFormat.format((date ?? DateTime.now()).toLocal());
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

    final results = await Future.wait([
      getDailyCashbox(today),
      if (userId == null)
        Future<List<CashSessionModel>>.value(const [])
      else
        CashRepository.listOpenSessionsForUser(userId: userId),
    ]);
    final cashboxToday = results[0] as CashboxDailyModel?;
    final openShifts = results[1] as List<CashSessionModel>;
    final userShift = openShifts.isEmpty ? null : openShifts.first;
    final linkedCashbox = userShift == null
        ? null
        : await _resolveCashboxForShift(userShift);
    final stale = (userShift != null && _isShiftOverMaxAge(userShift, nowMs))
        ? userShift
        : null;
    final activeSession =
        linkedCashbox != null &&
            linkedCashbox.businessDate == today &&
            linkedCashbox.isOpen &&
            userShift != null &&
            userShift.isOpen
        ? ActiveSession.fromModels(cashbox: linkedCashbox, shift: userShift)
        : null;

    return OperationGateState(
      businessDate: today,
      cashboxToday: cashboxToday,
      userOpenShift: userShift,
      staleOpenShift: stale,
      activeSession: activeSession,
    );
  }

  static Future<CashboxDailyModel?> _resolveCashboxForShift(
    CashSessionModel shift,
  ) async {
    final byId = await getDailyCashboxById(shift.cashboxDailyId);
    if (byId != null) return byId;

    final shiftBusinessDate = shift.businessDate?.trim();
    if (shiftBusinessDate == null || shiftBusinessDate.isEmpty) return null;
    return getDailyCashbox(shiftBusinessDate);
  }

  static Future<CashboxDailyModel> _repairCashboxForOpenShift(
    Transaction txn, {
    required CashSessionModel shift,
    required String fallbackBusinessDate,
    required int actorUserId,
    required int nowMs,
  }) async {
    final shiftId = shift.id;
    if (shiftId == null) {
      throw StateError('El turno abierto no tiene un identificador válido.');
    }

    final shiftBusinessDate = (shift.businessDate ?? '').trim();
    final cashboxBusinessDate = shiftBusinessDate.isNotEmpty
        ? shiftBusinessDate
        : fallbackBusinessDate.trim();
    if (cashboxBusinessDate.isEmpty) {
      throw StateError(
        'El turno abierto no tiene una fecha de negocio válida.',
      );
    }

    var cashboxRows = await txn.query(
      DbTables.cashboxDaily,
      where: 'business_date = ?',
      whereArgs: [cashboxBusinessDate],
      limit: 1,
    );

    Map<String, dynamic> repairedCashboxRow;
    if (cashboxRows.isEmpty) {
      final cashboxId = await txn.insert(DbTables.cashboxDaily, {
        'business_date': cashboxBusinessDate,
        'opened_at_ms': shift.openedAtMs,
        'opened_by_user_id': shift.userId,
        'initial_amount': shift.openingAmount,
        'current_amount': shift.openingAmount,
        'status': 'OPEN',
        'note':
            'Autorreparada desde turno abierto #$shiftId (${DateTime.now().toLocal()})',
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      cashboxRows = await txn.query(
        DbTables.cashboxDaily,
        where: 'id = ?',
        whereArgs: [cashboxId],
        limit: 1,
      );
      repairedCashboxRow = cashboxRows.first;
    } else {
      repairedCashboxRow = cashboxRows.first;
      final status = (repairedCashboxRow['status'] as String? ?? 'OPEN')
          .toUpperCase();
      if (status != 'OPEN') {
        final previousNote = (repairedCashboxRow['note'] as String? ?? '')
            .trim();
        final repairNote = [
          if (previousNote.isNotEmpty) previousNote,
          'Reabierta por turno abierto #$shiftId (${DateTime.now().toLocal()})',
        ].join('\n');

        await txn.update(
          DbTables.cashboxDaily,
          {
            'opened_at_ms': nowMs,
            'opened_by_user_id': actorUserId,
            'status': 'OPEN',
            'closed_at_ms': null,
            'closed_by_user_id': null,
            'note': repairNote,
          },
          where: 'id = ?',
          whereArgs: [repairedCashboxRow['id']],
        );
        cashboxRows = await txn.query(
          DbTables.cashboxDaily,
          where: 'id = ?',
          whereArgs: [repairedCashboxRow['id']],
          limit: 1,
        );
        repairedCashboxRow = cashboxRows.first;
      }
    }

    final repairedCashbox = CashboxDailyModel.fromMap(repairedCashboxRow);
    final repairedCashboxId = repairedCashbox.id;
    if (repairedCashboxId == null) {
      throw StateError(
        'No fue posible reparar la caja diaria del turno abierto.',
      );
    }

    await txn.update(
      DbTables.cashSessions,
      {
        'cashbox_daily_id': repairedCashboxId,
        'business_date': repairedCashbox.businessDate,
      },
      where: 'id = ?',
      whereArgs: [shiftId],
    );

    return repairedCashbox;
  }

  /// Sincroniza los metadatos de un turno que YA pertenece al usuario actual.
  /// A diferencia de la versión anterior, NUNCA cambia `opened_by_user_id`:
  /// cada usuario es dueño exclusivo de sus propios turnos.
  static Future<CashSessionModel> _syncOwnShiftMetadata(
    Transaction txn, {
    required Map<String, dynamic> row,
    required CashboxDailyModel cashbox,
    required int userId,
    required String userName,
  }) async {
    final shift = CashSessionModel.fromMap(row);
    final shiftId = shift.id;
    final cashboxId = cashbox.id;
    if (shiftId == null || cashboxId == null) {
      throw StateError('La sesión abierta no tiene identificadores válidos.');
    }

    // Seguridad: verificar que el turno realmente pertenece a este usuario.
    if (shift.userId != userId) {
      throw StateError(
        'El turno #$shiftId pertenece a otro usuario y no puede ser reasignado. '
        'Cada usuario debe abrir su propio turno.',
      );
    }

    final updates = <String, Object?>{};
    if (shift.userName.trim() != userName.trim()) {
      updates['user_name'] = userName;
    }
    if (shift.cashboxDailyId != cashboxId) {
      updates['cashbox_daily_id'] = cashboxId;
    }
    if ((shift.businessDate ?? '').trim() != cashbox.businessDate) {
      updates['business_date'] = cashbox.businessDate;
    }

    if (updates.isNotEmpty) {
      await txn.update(
        DbTables.cashSessions,
        updates,
        where: 'id = ? AND status = ? AND closed_at_ms IS NULL',
        whereArgs: [shiftId, CashSessionStatus.open],
      );
      final repairedRows = await txn.query(
        DbTables.cashSessions,
        where: 'id = ?',
        whereArgs: [shiftId],
        limit: 1,
      );
      if (repairedRows.isNotEmpty) {
        return CashSessionModel.fromMap(repairedRows.first);
      }
    }

    return shift;
  }

  static Future<CashboxDailyModel> _ensureCashboxForBusinessDate(
    Transaction txn, {
    required String businessDate,
    required int userId,
    required int nowMs,
    required double openingAmount,
    String? note,
  }) async {
    final rows = await txn.query(
      DbTables.cashboxDaily,
      where: 'business_date = ?',
      whereArgs: [businessDate],
      limit: 1,
    );

    if (rows.isEmpty) {
      final cashboxId = await txn.insert(DbTables.cashboxDaily, {
        'business_date': businessDate,
        'opened_at_ms': nowMs,
        'opened_by_user_id': userId,
        'initial_amount': openingAmount,
        'current_amount': openingAmount,
        'status': 'OPEN',
        'note': note,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      final inserted = await txn.query(
        DbTables.cashboxDaily,
        where: 'id = ?',
        whereArgs: [cashboxId],
        limit: 1,
      );
      return CashboxDailyModel.fromMap(inserted.first);
    }

    final row = rows.first;
    final status = (row['status'] as String? ?? 'OPEN').toUpperCase();
    if (status != 'OPEN') {
      await txn.update(
        DbTables.cashboxDaily,
        {
          'opened_at_ms': nowMs,
          'opened_by_user_id': userId,
          'initial_amount': openingAmount,
          'current_amount': openingAmount,
          'status': 'OPEN',
          'closed_at_ms': null,
          'closed_by_user_id': null,
          'note': note,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      final reopened = await txn.query(
        DbTables.cashboxDaily,
        where: 'id = ?',
        whereArgs: [row['id']],
        limit: 1,
      );
      return CashboxDailyModel.fromMap(reopened.first);
    }

    return CashboxDailyModel.fromMap(row);
  }

  static Future<CashSessionModel> _moveOpenShiftToBusinessDate(
    Transaction txn, {
    required CashSessionModel shift,
    required CashboxDailyModel? previousCashbox,
    required String businessDate,
    required int userId,
    required String userName,
    required int nowMs,
    required double openingAmount,
    String? note,
  }) async {
    final shiftId = shift.id;
    if (shiftId == null) {
      throw StateError('El turno abierto no tiene un identificador válido.');
    }

    final targetCashbox = await _ensureCashboxForBusinessDate(
      txn,
      businessDate: businessDate,
      userId: userId,
      nowMs: nowMs,
      openingAmount: openingAmount,
      note: note,
    );

    final movedShift = await _syncOwnShiftMetadata(
      txn,
      row: shift.toMap(),
      cashbox: targetCashbox,
      userId: userId,
      userName: userName,
    );

    final previousCashboxId = previousCashbox?.id;
    final previousBusinessDate = previousCashbox?.businessDate;
    if (previousCashboxId != null &&
        previousBusinessDate != null &&
        previousBusinessDate != businessDate) {
      final remainingRows = await txn.query(
        DbTables.cashSessions,
        columns: ['id'],
        where: '''
          status = 'OPEN'
          AND closed_at_ms IS NULL
          AND id <> ?
          AND (cashbox_daily_id = ? OR (cashbox_daily_id IS NULL AND business_date = ?))
        ''',
        whereArgs: [shiftId, previousCashboxId, previousBusinessDate],
        limit: 1,
      );
      if (remainingRows.isEmpty) {
        final previousNote = (previousCashbox?.note ?? '').trim();
        final repairNote = [
          if (previousNote.isNotEmpty) previousNote,
          'Cerrada automaticamente al mover turno #$shiftId a $businessDate (${DateTime.now().toLocal()})',
        ].join('\n');
        await txn.update(
          DbTables.cashboxDaily,
          {
            'status': 'CLOSED',
            'closed_at_ms': nowMs,
            'closed_by_user_id': userId,
            'note': repairNote,
          },
          where: 'id = ? AND status = ?',
          whereArgs: [previousCashboxId, 'OPEN'],
        );
      }
    }

    return movedShift.copyWith(
      cashboxDailyId: targetCashbox.id,
      businessDate: targetCashbox.businessDate,
      userId: userId,
      userName: userName,
    );
  }

  static Future<void> _retireDuplicateOpenShifts(
    Transaction txn, {
    required List<Map<String, dynamic>> rows,
    required int keepShiftId,
    required int actorUserId,
    required int nowMs,
  }) async {
    for (final row in rows) {
      final duplicateId = row['id'] as int?;
      if (duplicateId == null || duplicateId == keepShiftId) continue;

      final previousNote = (row['note'] as String? ?? '').trim();
      final repairNote = [
        if (previousNote.isNotEmpty) previousNote,
        'Cerrada automaticamente por apertura segura; se conserva turno #$keepShiftId (${DateTime.now().toLocal()})',
      ].join('\n');

      await txn.update(
        DbTables.cashSessions,
        {
          'closed_at_ms': nowMs,
          'closed_by_user_id': actorUserId,
          'status': CashSessionStatus.closed,
          'note': repairNote,
        },
        where: 'id = ? AND status = ? AND closed_at_ms IS NULL',
        whereArgs: [duplicateId, CashSessionStatus.open],
      );
    }
  }

  static void queueRestoredSessionNotice(ActiveSession session) {
    _pendingRestoredSessionNotice = session;
  }

  static ActiveSession? consumeRestoredSessionNotice() {
    final session = _pendingRestoredSessionNotice;
    _pendingRestoredSessionNotice = null;
    return session;
  }

  static Future<ActiveSession?> loadActiveSession() async {
    final gate = await loadGateState();
    return gate.activeSession;
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
          where:
              "status = 'OPEN' AND closed_at_ms IS NULL AND (cashbox_daily_id = ? OR (cashbox_daily_id IS NULL AND business_date = ?))",
          whereArgs: [existing.id, businessDate],
          orderBy: 'opened_at_ms DESC',
        );

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

        if (openRows.isNotEmpty) {
          final reopenedRows = await txn.query(
            DbTables.cashboxDaily,
            where: 'id = ?',
            whereArgs: [existing.id],
            limit: 1,
          );
          if (reopenedRows.isNotEmpty) {
            final reopenedCashbox = CashboxDailyModel.fromMap(
              reopenedRows.first,
            );
            // Solo procesamos turnos del usuario actual, nunca reasignamos
            // turnos de otros usuarios.
            final myOpenRows = openRows
                .where((r) => (r['opened_by_user_id'] as int?) == userId)
                .toList(growable: false);
            if (myOpenRows.isNotEmpty) {
              final shift = await _syncOwnShiftMetadata(
                txn,
                row: myOpenRows.first,
                cashbox: reopenedCashbox,
                userId: userId,
                userName:
                    await SessionManager.displayName() ??
                    await SessionManager.username() ??
                    'Usuario',
              );
              final shiftId = shift.id;
              if (shiftId != null && myOpenRows.length > 1) {
                await _retireDuplicateOpenShifts(
                  txn,
                  rows: myOpenRows,
                  keepShiftId: shiftId,
                  actorUserId: userId,
                  nowMs: now,
                );
              }
            }
          }
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
      );
      if (existingUserRows.isNotEmpty) {
        id = existingUserRows.first['id'] as int?;
        if (id != null && existingUserRows.length > 1) {
          await _retireDuplicateOpenShifts(
            txn,
            rows: existingUserRows,
            keepShiftId: id!,
            actorUserId: userId,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
        return;
      }

      // Seguridad: verificar que otros turnos abiertos en la misma caja
      // pertenecen a OTROS usuarios. NO reasignamos turnos ajenos.
      // Cada usuario debe abrir su propio turno.

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

  static Future<ActiveSession> startActiveSession({
    required double openingAmount,
    String? note,
  }) async {
    final businessDate = businessDateOf();
    final userId = await SessionManager.userId() ?? 1;
    final userName =
        await SessionManager.displayName() ??
        await SessionManager.username() ??
        'Usuario';
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await AppDb.database;

    ActiveSession? result;
    await db.transaction((txn) async {
      final currentCashboxRows = await txn.query(
        DbTables.cashboxDaily,
        where: 'business_date = ?',
        whereArgs: [businessDate],
        limit: 1,
      );

      Map<String, dynamic>? cashboxRow = currentCashboxRows.isEmpty
          ? null
          : currentCashboxRows.first;

      final currentUserRows = await txn.query(
        DbTables.cashSessions,
        where: '''
          status = 'OPEN'
          AND closed_at_ms IS NULL
          AND opened_by_user_id = ?
        ''',
        whereArgs: [userId],
        orderBy: 'opened_at_ms DESC',
      );

      if (currentUserRows.isNotEmpty) {
        final shift = CashSessionModel.fromMap(currentUserRows.first);
        final shiftId = shift.id;
        if (shiftId != null && currentUserRows.length > 1) {
          await _retireDuplicateOpenShifts(
            txn,
            rows: currentUserRows,
            keepShiftId: shiftId,
            actorUserId: userId,
            nowMs: now,
          );
        }
        final linkedCashboxRows = shift.cashboxDailyId == null
            ? await txn.query(
                DbTables.cashboxDaily,
                where: 'business_date = ?',
                whereArgs: [shift.businessDate],
                limit: 1,
              )
            : await txn.query(
                DbTables.cashboxDaily,
                where: 'id = ?',
                whereArgs: [shift.cashboxDailyId],
                limit: 1,
              );
        if (linkedCashboxRows.isEmpty) {
          final shiftBusinessDate = (shift.businessDate ?? '').trim();
          if (shiftBusinessDate.isNotEmpty &&
              shiftBusinessDate != businessDate) {
            final movedShift = await _moveOpenShiftToBusinessDate(
              txn,
              shift: shift,
              previousCashbox: null,
              businessDate: businessDate,
              userId: userId,
              userName: userName,
              nowMs: now,
              openingAmount: openingAmount,
              note: note,
            );
            final movedCashboxRows = await txn.query(
              DbTables.cashboxDaily,
              where: 'id = ?',
              whereArgs: [movedShift.cashboxDailyId],
              limit: 1,
            );
            result = ActiveSession.fromModels(
              cashbox: CashboxDailyModel.fromMap(movedCashboxRows.first),
              shift: movedShift,
            );
            return;
          }
          final repairedCashbox = await _repairCashboxForOpenShift(
            txn,
            shift: shift,
            fallbackBusinessDate: businessDate,
            actorUserId: userId,
            nowMs: now,
          );
          result = ActiveSession.fromModels(
            cashbox: repairedCashbox,
            shift: shift.copyWith(
              cashboxDailyId: repairedCashbox.id,
              businessDate: repairedCashbox.businessDate,
            ),
          );
          return;
        }
        final linkedCashbox = CashboxDailyModel.fromMap(
          linkedCashboxRows.first,
        );
        if (linkedCashbox.businessDate != businessDate) {
          final movedShift = await _moveOpenShiftToBusinessDate(
            txn,
            shift: shift,
            previousCashbox: linkedCashbox,
            businessDate: businessDate,
            userId: userId,
            userName: userName,
            nowMs: now,
            openingAmount: openingAmount,
            note: note,
          );
          final movedCashboxRows = await txn.query(
            DbTables.cashboxDaily,
            where: 'id = ?',
            whereArgs: [movedShift.cashboxDailyId],
            limit: 1,
          );
          result = ActiveSession.fromModels(
            cashbox: CashboxDailyModel.fromMap(movedCashboxRows.first),
            shift: movedShift,
          );
          return;
        }
        if (!linkedCashbox.isOpen) {
          final repairedCashbox = await _repairCashboxForOpenShift(
            txn,
            shift: shift,
            fallbackBusinessDate: businessDate,
            actorUserId: userId,
            nowMs: now,
          );
          result = ActiveSession.fromModels(
            cashbox: repairedCashbox,
            shift: shift.copyWith(
              cashboxDailyId: repairedCashbox.id,
              businessDate: repairedCashbox.businessDate,
            ),
          );
          return;
        }
        result = ActiveSession.fromModels(cashbox: linkedCashbox, shift: shift);
        return;
      }

      if (cashboxRow == null) {
        final cashboxId = await txn.insert(DbTables.cashboxDaily, {
          'business_date': businessDate,
          'opened_at_ms': now,
          'opened_by_user_id': userId,
          'initial_amount': openingAmount,
          'current_amount': openingAmount,
          'status': 'OPEN',
          'note': note,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        final inserted = await txn.query(
          DbTables.cashboxDaily,
          where: 'id = ?',
          whereArgs: [cashboxId],
          limit: 1,
        );
        cashboxRow = inserted.first;
      } else if ((cashboxRow['status'] as String? ?? 'OPEN').toUpperCase() !=
          'OPEN') {
        await txn.update(
          DbTables.cashboxDaily,
          {
            'opened_at_ms': now,
            'opened_by_user_id': userId,
            'initial_amount': openingAmount,
            'current_amount': openingAmount,
            'status': 'OPEN',
            'closed_at_ms': null,
            'closed_by_user_id': null,
            'note': note,
          },
          where: 'id = ?',
          whereArgs: [cashboxRow['id']],
        );
        final reopened = await txn.query(
          DbTables.cashboxDaily,
          where: 'id = ?',
          whereArgs: [cashboxRow['id']],
          limit: 1,
        );
        cashboxRow = reopened.first;
      }

      final cashbox = CashboxDailyModel.fromMap(cashboxRow);

      // Seguridad: si existen turnos abiertos de OTROS usuarios en la misma
      // caja, los ignoramos. Cada usuario crea y gestiona su propio turno.

      var resolvedOpeningAmount = openingAmount;
      if (cashbox.isOpen && resolvedOpeningAmount.abs() < 1e-9) {
        resolvedOpeningAmount = cashbox.currentAmount;
      }

      final shiftId = await txn.insert(DbTables.cashSessions, {
        'opened_by_user_id': userId,
        'user_name': userName,
        'opened_at_ms': now,
        'initial_amount': resolvedOpeningAmount,
        'cashbox_daily_id': cashbox.id,
        'business_date': businessDate,
        'requires_closure': 0,
        'status': 'OPEN',
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      result = ActiveSession(
        userId: userId,
        cashId: cashbox.id!,
        shiftId: shiftId,
        openedAt: now,
        status: CashSessionStatus.open,
        userName: userName,
        businessDate: businessDate,
      );
    });

    if (result == null) {
      throw Exception('No fue posible iniciar la sesión activa.');
    }
    return result!;
  }

  static Future<ActiveSession> ensureActiveSessionForCurrentUser({
    required double openingAmount,
    String? note,
  }) {
    return startActiveSession(openingAmount: openingAmount, note: note);
  }

  static Future<CashSummaryModel> closeActiveSession({
    required int sessionId,
    required double closingAmount,
    String note = '',
  }) async {
    final userId = await SessionManager.userId();
    if (userId == null) {
      throw const AppException(
        type: AppErrorType.unauthorized,
        code: 'cash_close_user_missing',
        messageUser:
            'No se pudo confirmar el usuario actual. Cierra sesión, vuelve a iniciar y reintenta.',
        messageDev: 'No se pudo identificar al usuario para cerrar el turno.',
      );
    }

    final session = await CashRepository.getSessionById(sessionId);
    if (session == null || session.id == null) {
      throw const AppException(
        type: AppErrorType.notFound,
        code: 'cash_close_shift_missing',
        messageUser:
            'No encontramos un turno abierto para cerrar. Actualiza la pantalla y vuelve a intentarlo.',
        messageDev: 'No existe una sesión activa para cerrar.',
      );
    }

    // FULLPOS SEGURIDAD: verificar ownership antes de continuar.
    if (session.userId != userId) {
      throw AppException(
        type: AppErrorType.forbidden,
        code: 'cash_close_owner_mismatch',
        messageUser:
            'Este turno pertenece a otro usuario. Inicia sesión con el cajero correcto o pide a un supervisor que lo revise.',
        messageDev:
            'El turno #$sessionId pertenece al usuario ${session.userId}, no al usuario actual $userId.',
      );
    }

    final closeDailyCashbox = await _shouldCloseDailyCashboxAfterShift(
      session: session,
      closingSessionId: sessionId,
    );
    final summary = await CashRepository.buildSummary(sessionId: sessionId);
    await CashRepository.closeSession(
      sessionId: sessionId,
      closingAmount: closingAmount,
      note: note,
      summary: summary,
      expectedUserId: userId,
      expectedCashboxDailyId: session.cashboxDailyId,
      closeCashboxDaily: closeDailyCashbox,
      cashboxCloseNote: note,
      cashboxClosedByUserId: userId,
    );
    return summary;
  }

  static Future<bool> _shouldCloseDailyCashboxAfterShift({
    required CashSessionModel session,
    required int closingSessionId,
  }) async {
    final cashboxDailyId = session.cashboxDailyId;
    final businessDate = session.businessDate;

    if (cashboxDailyId == null &&
        (businessDate == null || businessDate.trim().isEmpty)) {
      return true;
    }

    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.cashSessions,
      columns: ['id'],
      where: '''
        status = 'OPEN'
        AND closed_at_ms IS NULL
        AND id <> ?
        AND (
          (? IS NOT NULL AND cashbox_daily_id = ?)
          OR (? IS NOT NULL AND cashbox_daily_id IS NULL AND business_date = ?)
        )
      ''',
      whereArgs: [
        closingSessionId,
        cashboxDailyId,
        cashboxDailyId,
        businessDate,
        businessDate,
      ],
      limit: 1,
    );
    return rows.isEmpty;
  }

  static Future<CashSummaryModel> closeSessionAndCashbox({
    required int sessionId,
    required double closingAmount,
    String note = '',
  }) {
    return closeActiveSession(
      sessionId: sessionId,
      closingAmount: closingAmount,
      note: note,
    );
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

    await closeActiveSession(
      sessionId: openShift.id!,
      closingAmount: closingAmount,
      note: note,
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

  static Future<CashSummaryModel?> buildActiveSessionSummary() async {
    final activeSession = await loadActiveSession();
    if (activeSession == null) return null;
    return CashRepository.buildSummary(sessionId: activeSession.shiftId);
  }
}
