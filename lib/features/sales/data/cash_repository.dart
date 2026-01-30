import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'cash_session_model.dart';
import 'cash_movement_model.dart';

/// Repositorio para gestión de caja/sesiones
class CashRepository {
  CashRepository._();

  /// Abre una nueva sesión de caja
  static Future<int> openSession({
    required int userId,
    required double initialAmount,
    String? notes,
  }) async {
    final db = await AppDb.database;
    
    // Verificar que no haya sesión abierta
    final openSessions = await getOpenSessions();
    if (openSessions.isNotEmpty) {
      throw Exception('Ya existe una sesión abierta');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final session = CashSessionModel(
      id: null,
      openedByUserId: userId,
      openedAtMs: now,
      initialAmount: initialAmount,
      closedAtMs: null,
      closedByUserId: null,
      note: notes,
    );

    return await db.insert(DbTables.cashSessions, session.toMap());
  }

  /// Cierra la sesión actual
  static Future<void> closeSession({
    required int sessionId,
    required int userId,
    required double finalAmount,
    String? notes,
  }) async {
    final db = await AppDb.database;
    
    final session = await getById(sessionId);
    if (session == null) {
      throw Exception('Sesión no encontrada');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      DbTables.cashSessions,
      {
        'closed_at_ms': now,
        'closed_by_user_id': userId,
        'note': notes,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Agrega un movimiento de caja (entrada/salida)
  static Future<int> addMovement({
    required int sessionId,
    required String movementType, // 'in' o 'out'
    required double amount,
    String? reason,
    String? notes,
  }) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final movement = CashMovementModel(
      id: null,
      sessionId: sessionId,
      type: movementType,
      amount: amount,
      note: notes,
      createdAtMs: now,
    );

    return await db.insert(DbTables.cashMovements, movement.toMap());
  }

  /// Obtiene la sesión actual abierta
  static Future<CashSessionModel?> getCurrentSession() async {
    final sessions = await getOpenSessions();
    return sessions.isEmpty ? null : sessions.first;
  }

  /// Obtiene todas las sesiones abiertas
  static Future<List<CashSessionModel>> getOpenSessions() async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.cashSessions,
      where: 'closed_at_ms IS NULL',
      orderBy: 'opened_at_ms DESC',
    );
    return maps.map((m) => CashSessionModel.fromMap(m)).toList();
  }

  /// Obtiene una sesión por ID
  static Future<CashSessionModel?> getById(int id) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.cashSessions,
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isEmpty ? null : CashSessionModel.fromMap(maps.first);
  }

  /// Lista todas las sesiones
  static Future<List<CashSessionModel>> getAll({
    int? userId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 50,
  }) async {
    final db = await AppDb.database;
    
    String where = '1=1';
    List<dynamic> args = [];
    
    if (userId != null) {
      where += ' AND opened_by_user_id = ?';
      args.add(userId);
    }
    if (fromDate != null) {
      where += ' AND opened_at_ms >= ?';
      args.add(fromDate.millisecondsSinceEpoch);
    }
    if (toDate != null) {
      where += ' AND opened_at_ms <= ?';
      args.add(toDate.millisecondsSinceEpoch);
    }
    
    final maps = await db.query(
      DbTables.cashSessions,
      where: where,
      whereArgs: args,
      orderBy: 'opened_at_ms DESC',
      limit: limit,
    );
    
    return maps.map((m) => CashSessionModel.fromMap(m)).toList();
  }

  /// Obtiene movimientos de una sesión
  static Future<List<CashMovementModel>> getMovementsBySession(int sessionId) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.cashMovements,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at_ms DESC',
    );
    return maps.map((m) => CashMovementModel.fromMap(m)).toList();
  }

  /// Calcula totales de una sesión
  static Future<Map<String, double>> calculateSessionTotals(int sessionId) async {
    final movements = await getMovementsBySession(sessionId);
    double totalIn = 0.0;
    double totalOut = 0.0;

    for (var mov in movements) {
      if (mov.type == 'in') {
        totalIn += mov.amount;
      } else {
        totalOut += mov.amount;
      }
    }

    return {
      'totalIn': totalIn,
      'totalOut': totalOut,
      'balance': totalIn - totalOut,
    };
  }
}
