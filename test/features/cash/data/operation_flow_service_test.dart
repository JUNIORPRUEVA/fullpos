import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/features/cash/data/operation_flow_service.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory(p.join(root.path, 'support'));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = Directory(p.join(root.path, 'documents'));
    await dir.create(recursive: true);
    return dir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fullpos_cash_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({
      'flutter.logged_user_id': 1,
      'flutter.logged_user': 'admin',
      'flutter.logged_display_name': 'Admin',
    });
    await AppDb.resetForTests();
  });

  tearDown(() async {
    await AppDb.resetForTests();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('repara turno abierto sin caja diaria asociada al abrir caja', () async {
    final db = await AppDb.database;
    final orphanBusinessDate = OperationFlowService.businessDateOf();
    final openedAt = DateTime.now().millisecondsSinceEpoch;
    final shiftId = await db.insert(DbTables.cashSessions, {
      'opened_by_user_id': 1,
      'user_name': 'Admin',
      'opened_at_ms': openedAt,
      'initial_amount': 500.0,
      'cashbox_daily_id': null,
      'business_date': orphanBusinessDate,
      'requires_closure': 0,
      'status': 'OPEN',
    });

    final session = await OperationFlowService.startActiveSession(
      openingAmount: 1000,
      note: 'apertura de prueba',
    );

    expect(session.shiftId, shiftId);
    expect(session.businessDate, orphanBusinessDate);

    final repairedShift = await db.query(
      DbTables.cashSessions,
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    final repairedCashboxId = repairedShift.first['cashbox_daily_id'] as int?;
    expect(repairedCashboxId, isNotNull);
    expect(repairedShift.first['business_date'], orphanBusinessDate);

    final repairedCashbox = await db.query(
      DbTables.cashboxDaily,
      where: 'id = ?',
      whereArgs: [repairedCashboxId],
      limit: 1,
    );
    expect(repairedCashbox, hasLength(1));
    expect(repairedCashbox.first['business_date'], orphanBusinessDate);
    expect(repairedCashbox.first['status'], 'OPEN');

    final todayRows = await db.query(
      DbTables.cashboxDaily,
      where: 'business_date = ?',
      whereArgs: [OperationFlowService.businessDateOf()],
    );
    expect(todayRows, hasLength(1));
  });

  test(
    'abre turno propio aunque otro usuario tenga turno abierto en la misma caja',
    () async {
      SharedPreferences.setMockInitialValues({
        'flutter.logged_user_id': 2,
        'flutter.logged_user': 'cajero',
        'flutter.logged_display_name': 'Cajero',
      });

      final db = await AppDb.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(DbTables.users, {
        'id': 2,
        'company_id': 1,
        'username': 'cajero',
        'pin': null,
        'role': 'cashier',
        'is_active': 1,
        'created_at_ms': now,
        'updated_at_ms': now,
      });

      final businessDate = OperationFlowService.businessDateOf();
      final cashboxId = await db.insert(DbTables.cashboxDaily, {
        'business_date': businessDate,
        'opened_at_ms': now,
        'opened_by_user_id': 1,
        'initial_amount': 1000.0,
        'current_amount': 1000.0,
        'status': 'OPEN',
        'note': 'caja previa',
      });
      final shiftId = await db.insert(DbTables.cashSessions, {
        'opened_by_user_id': 1,
        'user_name': 'Admin',
        'opened_at_ms': now,
        'initial_amount': 1000.0,
        'cashbox_daily_id': cashboxId,
        'business_date': businessDate,
        'requires_closure': 0,
        'status': 'OPEN',
      });

      final session = await OperationFlowService.startActiveSession(
        openingAmount: 500,
        note: 'intento nuevo',
      );

      expect(session.shiftId, isNot(shiftId));
      expect(session.cashId, cashboxId);
      expect(session.userId, 2);
      expect(session.userName, 'Cajero');

      final shifts = await db.query(
        DbTables.cashSessions,
        where: 'cashbox_daily_id = ? AND status = ? AND closed_at_ms IS NULL',
        whereArgs: [cashboxId, 'OPEN'],
        orderBy: 'opened_by_user_id ASC',
      );
      expect(shifts, hasLength(2));
      expect(shifts.map((row) => row['opened_by_user_id']), [1, 2]);
      expect(shifts.map((row) => row['user_name']), ['Admin', 'Cajero']);
    },
  );

  test(
    'cierra el turno actual sin cerrar la caja si otro turno sigue abierto',
    () async {
      final firstSession = await OperationFlowService.startActiveSession(
        openingAmount: 1000,
        note: 'turno admin',
      );

      final db = await AppDb.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(DbTables.users, {
        'id': 2,
        'company_id': 1,
        'username': 'cajero',
        'pin': null,
        'role': 'cashier',
        'is_active': 1,
        'created_at_ms': now,
        'updated_at_ms': now,
      });

      await SessionManager.login(
        userId: 2,
        username: 'cajero',
        displayName: 'Cajero',
        role: 'cashier',
        terminalId: 'terminal-test',
      );

      final secondSession = await OperationFlowService.startActiveSession(
        openingAmount: 500,
        note: 'turno cajero',
      );

      await OperationFlowService.closeActiveSession(
        sessionId: secondSession.shiftId,
        closingAmount: 500,
        note: 'cierre cajero',
      );

      final shifts = await db.query(
        DbTables.cashSessions,
        where: 'id IN (?, ?)',
        whereArgs: [firstSession.shiftId, secondSession.shiftId],
        orderBy: 'id ASC',
      );
      final firstShift = shifts.firstWhere(
        (row) => row['id'] == firstSession.shiftId,
      );
      final secondShift = shifts.firstWhere(
        (row) => row['id'] == secondSession.shiftId,
      );

      expect(firstShift['status'], 'OPEN');
      expect(firstShift['closed_at_ms'], isNull);
      expect(secondShift['status'], 'CLOSED');
      expect(secondShift['closed_at_ms'], isNotNull);

      final cashboxRows = await db.query(
        DbTables.cashboxDaily,
        where: 'id = ?',
        whereArgs: [firstSession.cashId],
        limit: 1,
      );
      expect(cashboxRows.first['status'], 'OPEN');
    },
  );

  test(
    'repara esquema legacy con cashbox_daily_id unico y permite turnos por usuario',
    () async {
      final db = await AppDb.database;
      await db.execute('PRAGMA foreign_keys = OFF;');
      await db.execute('DROP TABLE ${DbTables.cashSessions};');
      await db.execute('''
        CREATE TABLE ${DbTables.cashSessions} (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          opened_by_user_id INTEGER NOT NULL,
          user_name TEXT NOT NULL DEFAULT 'admin',
          opened_at_ms INTEGER NOT NULL,
          initial_amount REAL NOT NULL DEFAULT 0,
          cashbox_daily_id INTEGER UNIQUE,
          business_date TEXT,
          requires_closure INTEGER NOT NULL DEFAULT 0,
          closing_amount REAL,
          expected_cash REAL,
          difference REAL,
          closed_at_ms INTEGER,
          closed_by_user_id INTEGER,
          note TEXT,
          status TEXT NOT NULL DEFAULT 'OPEN'
        )
      ''');
      await db.execute('PRAGMA foreign_keys = ON;');

      await AppDb.ensureSchema(db);

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(DbTables.users, {
        'id': 2,
        'company_id': 1,
        'username': 'junior',
        'pin': null,
        'role': 'cashier',
        'is_active': 1,
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      final businessDate = OperationFlowService.businessDateOf();
      final cashboxId = await db.insert(DbTables.cashboxDaily, {
        'business_date': businessDate,
        'opened_at_ms': now,
        'opened_by_user_id': 1,
        'initial_amount': 0.0,
        'current_amount': 0.0,
        'status': 'OPEN',
      });

      await db.insert(DbTables.cashSessions, {
        'opened_by_user_id': 1,
        'user_name': 'Admin',
        'opened_at_ms': now,
        'initial_amount': 0.0,
        'cashbox_daily_id': cashboxId,
        'business_date': businessDate,
        'requires_closure': 0,
        'status': 'OPEN',
      });

      SharedPreferences.setMockInitialValues({
        'flutter.logged_user_id': 2,
        'flutter.logged_user': 'junior',
        'flutter.logged_display_name': 'Junior',
      });

      final session = await OperationFlowService.startActiveSession(
        openingAmount: 0,
        note: 'apertura junior',
      );

      expect(session.userId, 2);
      expect(session.cashId, cashboxId);

      final openRows = await db.query(
        DbTables.cashSessions,
        where: 'cashbox_daily_id = ? AND status = ? AND closed_at_ms IS NULL',
        whereArgs: [cashboxId, 'OPEN'],
      );
      expect(openRows, hasLength(2));
    },
  );

  test('consolida turnos duplicados al iniciar caja', () async {
    final db = await AppDb.database;
    await db.execute(
      'DROP INDEX IF EXISTS idx_cash_sessions_unique_open_per_user',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final businessDate = OperationFlowService.businessDateOf();
    final cashboxId = await db.insert(DbTables.cashboxDaily, {
      'business_date': businessDate,
      'opened_at_ms': now,
      'opened_by_user_id': 1,
      'initial_amount': 800.0,
      'current_amount': 800.0,
      'status': 'OPEN',
      'note': 'caja duplicada',
    });
    final olderShiftId = await db.insert(DbTables.cashSessions, {
      'opened_by_user_id': 1,
      'user_name': 'Admin',
      'opened_at_ms': now - 1000,
      'initial_amount': 800.0,
      'cashbox_daily_id': cashboxId,
      'business_date': businessDate,
      'requires_closure': 0,
      'status': 'OPEN',
    });
    final newestShiftId = await db.insert(DbTables.cashSessions, {
      'opened_by_user_id': 1,
      'user_name': 'Admin',
      'opened_at_ms': now,
      'initial_amount': 800.0,
      'cashbox_daily_id': cashboxId,
      'business_date': businessDate,
      'requires_closure': 0,
      'status': 'OPEN',
    });

    final session = await OperationFlowService.startActiveSession(
      openingAmount: 800,
      note: '',
    );

    expect(session.shiftId, newestShiftId);

    final openRows = await db.query(
      DbTables.cashSessions,
      where: 'status = ? AND closed_at_ms IS NULL',
      whereArgs: ['OPEN'],
    );
    expect(openRows, hasLength(1));
    expect(openRows.first['id'], newestShiftId);

    final olderRows = await db.query(
      DbTables.cashSessions,
      where: 'id = ?',
      whereArgs: [olderShiftId],
      limit: 1,
    );
    expect(olderRows.first['status'], 'CLOSED');
    expect(olderRows.first['closed_at_ms'], isNotNull);
  });

  test('reabre caja cerrada con turno abierto sin lanzar error', () async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final businessDate = OperationFlowService.businessDateOf();
    final cashboxId = await db.insert(DbTables.cashboxDaily, {
      'business_date': businessDate,
      'opened_at_ms': now - 2000,
      'opened_by_user_id': 1,
      'initial_amount': 300.0,
      'current_amount': 300.0,
      'status': 'CLOSED',
      'closed_at_ms': now - 1000,
      'closed_by_user_id': 1,
      'note': 'cierre inconsistente',
    });
    final shiftId = await db.insert(DbTables.cashSessions, {
      'opened_by_user_id': 1,
      'user_name': 'Admin',
      'opened_at_ms': now - 2000,
      'initial_amount': 300.0,
      'cashbox_daily_id': cashboxId,
      'business_date': businessDate,
      'requires_closure': 0,
      'status': 'OPEN',
    });

    final cashbox = await OperationFlowService.openDailyCashboxToday(
      openingAmount: 300,
      note: 'reapertura segura',
    );

    expect(cashbox.id, cashboxId);
    expect(cashbox.status, 'OPEN');
    expect(cashbox.closedAtMs, isNull);

    final shifts = await db.query(
      DbTables.cashSessions,
      where: 'status = ? AND closed_at_ms IS NULL',
      whereArgs: ['OPEN'],
    );
    expect(shifts, hasLength(1));
    expect(shifts.first['id'], shiftId);
    expect(shifts.first['cashbox_daily_id'], cashboxId);
  });

  test('mueve turno reciente de fecha anterior a la caja de hoy', () async {
    final db = await AppDb.database;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final previousBusinessDate = OperationFlowService.businessDateOf(
      now.subtract(const Duration(days: 1)),
    );
    final today = OperationFlowService.businessDateOf(now);

    final oldCashboxId = await db.insert(DbTables.cashboxDaily, {
      'business_date': previousBusinessDate,
      'opened_at_ms': nowMs - const Duration(hours: 1).inMilliseconds,
      'opened_by_user_id': 1,
      'initial_amount': 1200.0,
      'current_amount': 1200.0,
      'status': 'OPEN',
      'note': 'caja previa por actualizacion',
    });
    final shiftId = await db.insert(DbTables.cashSessions, {
      'opened_by_user_id': 1,
      'user_name': 'Admin',
      'opened_at_ms': nowMs - const Duration(hours: 1).inMilliseconds,
      'initial_amount': 1200.0,
      'cashbox_daily_id': oldCashboxId,
      'business_date': previousBusinessDate,
      'requires_closure': 0,
      'status': 'OPEN',
    });

    expect(await OperationFlowService.loadActiveSession(), isNull);

    final session = await OperationFlowService.startActiveSession(
      openingAmount: 1200,
      note: 'recuperacion tras actualizacion',
    );

    expect(session.shiftId, shiftId);
    expect(session.businessDate, today);

    final movedShift = await db.query(
      DbTables.cashSessions,
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    expect(movedShift.first['business_date'], today);
    expect(movedShift.first['cashbox_daily_id'], isNot(oldCashboxId));

    final oldCashbox = await db.query(
      DbTables.cashboxDaily,
      where: 'id = ?',
      whereArgs: [oldCashboxId],
      limit: 1,
    );
    expect(oldCashbox.first['status'], 'CLOSED');

    final todayCashbox = await db.query(
      DbTables.cashboxDaily,
      where: 'business_date = ?',
      whereArgs: [today],
      limit: 1,
    );
    expect(todayCashbox, hasLength(1));
    expect(todayCashbox.first['status'], 'OPEN');
  });

  test(
    'mueve turno antiguo de fecha anterior para evitar rebote al gate',
    () async {
      final db = await AppDb.database;
      final now = DateTime.now();
      final oldOpenedAt = now.subtract(const Duration(days: 3));
      final oldOpenedAtMs = oldOpenedAt.millisecondsSinceEpoch;
      final previousBusinessDate = OperationFlowService.businessDateOf(
        oldOpenedAt,
      );
      final today = OperationFlowService.businessDateOf(now);

      final oldCashboxId = await db.insert(DbTables.cashboxDaily, {
        'business_date': previousBusinessDate,
        'opened_at_ms': oldOpenedAtMs,
        'opened_by_user_id': 1,
        'initial_amount': 900.0,
        'current_amount': 900.0,
        'status': 'OPEN',
        'note': 'turno viejo antes de actualizar',
      });
      final shiftId = await db.insert(DbTables.cashSessions, {
        'opened_by_user_id': 1,
        'user_name': 'Admin',
        'opened_at_ms': oldOpenedAtMs,
        'initial_amount': 900.0,
        'cashbox_daily_id': oldCashboxId,
        'business_date': previousBusinessDate,
        'requires_closure': 0,
        'status': 'OPEN',
      });

      expect(await OperationFlowService.loadActiveSession(), isNull);

      final session = await OperationFlowService.startActiveSession(
        openingAmount: 10000,
        note: 'apertura despues de actualizacion',
      );

      expect(session.shiftId, shiftId);
      expect(session.businessDate, today);

      final active = await OperationFlowService.loadActiveSession();
      expect(active, isNotNull);
      expect(active!.shiftId, shiftId);
      expect(active.businessDate, today);

      final movedShift = await db.query(
        DbTables.cashSessions,
        where: 'id = ?',
        whereArgs: [shiftId],
        limit: 1,
      );
      expect(movedShift.first['business_date'], today);
      expect(movedShift.first['cashbox_daily_id'], isNot(oldCashboxId));
    },
  );
}
