import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/features/cash/data/cash_repository.dart';
import 'package:fullpos/features/cash/data/cash_summary_model.dart';
import 'package:fullpos/features/cash/data/operation_flow_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this._docsDir);

  final Directory _docsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsDir.path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(_docsDir.path, 'support');
}

Future<void> _seedUsers(Database db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert(DbTables.users, {
    'id': 1,
    'company_id': 1,
    'username': 'admin',
    'pin': '9999',
    'role': 'admin',
    'is_active': 1,
    'created_at_ms': now,
    'updated_at_ms': now,
    'display_name': 'Admin',
    'permissions': null,
    'password_hash':
        '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
    'deleted_at_ms': null,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert(DbTables.users, {
    'id': 2,
    'company_id': 1,
    'username': 'cashier2',
    'pin': null,
    'role': 'cashier',
    'is_active': 1,
    'created_at_ms': now,
    'updated_at_ms': now,
    'display_name': 'Cashier 2',
    'permissions': null,
    'password_hash':
        'b4c94003c562bb0d89535eca77f07284fe560fd48a7cc1ed99f0a56263d616ba',
    'deleted_at_ms': null,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _cleanCashTables(Database db) async {
  await db.delete(DbTables.cashMovements);
  await db.delete(DbTables.sales);
  await db.delete(DbTables.posTicketItems);
  await db.delete(DbTables.posTickets);
  await db.delete(DbTables.tempCartItems);
  await db.delete(DbTables.tempCarts);
  await db.delete(DbTables.cashSessions);
  await db.delete(DbTables.cashboxDaily);
}

Future<int> _insertCashboxToday(Database db) async {
  final businessDate = OperationFlowService.businessDateOf();
  return db.insert(DbTables.cashboxDaily, {
    'business_date': businessDate,
    'opened_at_ms': DateTime.now().millisecondsSinceEpoch,
    'opened_by_user_id': 1,
    'initial_amount': 100.0,
    'status': 'OPEN',
    'note': 'test',
  }, conflictAlgorithm: ConflictAlgorithm.abort);
}

Future<int> _insertCashboxTodayWithAmount(Database db, double amount) async {
  final businessDate = OperationFlowService.businessDateOf();
  return db.insert(DbTables.cashboxDaily, {
    'business_date': businessDate,
    'opened_at_ms': DateTime.now().millisecondsSinceEpoch,
    'opened_by_user_id': 1,
    'initial_amount': amount,
    'status': 'OPEN',
    'note': 'test',
  }, conflictAlgorithm: ConflictAlgorithm.abort);
}

Future<int> _insertOpenShift(
  Database db, {
  required int userId,
  required String userName,
  required int cashboxId,
  String? businessDate,
  int? openedAtMs,
}) async {
  return db.insert(DbTables.cashSessions, {
    'opened_by_user_id': userId,
    'user_name': userName,
    'opened_at_ms': openedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    'initial_amount': 0.0,
    'cashbox_daily_id': cashboxId,
    'business_date': businessDate ?? OperationFlowService.businessDateOf(),
    'requires_closure': 0,
    'status': 'OPEN',
  }, conflictAlgorithm: ConflictAlgorithm.abort);
}

Future<String> _yesterdayBusinessDate() async {
  final today = DateTime.now().toLocal();
  final y = today.subtract(const Duration(days: 1));
  return OperationFlowService.businessDateOf(y);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUpAll(() async {
    DbInit.ensureInitialized();
    docsDir = await Directory.systemTemp.createTemp('fullpos_cash_harden_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
    SharedPreferences.setMockInitialValues({});

    await AppDb.resetForTests();
    final db = await AppDb.database;
    await _seedUsers(db);
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SessionManager.logout();
    final db = await AppDb.database;
    await _cleanCashTables(db);
    await _seedUsers(db);
  });

  group('Cash/Shift hardening', () {
    test('gate only forces cut after 48 hours', () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxToday(db);

      await SessionManager.login(
        userId: 1,
        username: 'admin',
        displayName: 'Admin',
        role: 'admin',
      );

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Caso 1: turno abierto hace 47h -> debe permitir operar.
      await _insertOpenShift(
        db,
        userId: 1,
        userName: 'Admin',
        cashboxId: cashboxId,
        openedAtMs: nowMs - const Duration(hours: 47).inMilliseconds,
      );
      var gate = await OperationFlowService.loadGateState();
      expect(gate.hasUserShiftOpen, isTrue);
      expect(gate.hasStaleShift, isFalse);
      expect(gate.canOperate, isTrue);

      // Caso 2: turno abierto hace 49h -> debe forzar corte antes de operar.
      await db.delete(DbTables.cashSessions);
      await _insertOpenShift(
        db,
        userId: 1,
        userName: 'Admin',
        cashboxId: cashboxId,
        openedAtMs: nowMs - const Duration(hours: 49).inMilliseconds,
      );
      gate = await OperationFlowService.loadGateState();
      expect(gate.hasUserShiftOpen, isTrue);
      expect(gate.hasStaleShift, isTrue);
      expect(gate.canOperate, isFalse);
    });

    test(
      'openShiftForCurrentUser carries forward last closed shift closing amount when openingAmount=0',
      () async {
        final db = await AppDb.database;
        await _insertCashboxTodayWithAmount(db, 3000.0);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final shift1 = await OperationFlowService.openShiftForCurrentUser(
          openingAmount: 0,
        );
        expect(shift1.openingAmount, 3000.0);

        await OperationFlowService.closeOpenShiftForCurrentUser(
          closingAmount: 3100.0,
          note: 'cierre 1',
        );

        final shift2 = await OperationFlowService.openShiftForCurrentUser(
          openingAmount: 0,
        );
        expect(shift2.openingAmount, 3100.0);
      },
    );

    test(
      'openDailyCashboxToday updates initial amount if cashbox already OPEN and no shifts yet',
      () async {
        final db = await AppDb.database;
        await _insertCashboxTodayWithAmount(db, 0.0);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final cashbox = await OperationFlowService.openDailyCashboxToday(
          openingAmount: 100.0,
          note: 'Apertura test',
        );
        expect(cashbox.initialAmount, 100.0);
      },
    );

    test(
      'openShiftForCurrentUser inherits daily cashbox initial amount for the first shift when openingAmount=0',
      () async {
        final db = await AppDb.database;
        await _insertCashboxToday(db);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final shift = await OperationFlowService.openShiftForCurrentUser(
          openingAmount: 0,
        );
        expect(shift.openingAmount, 100.0);
        expect(shift.cashboxDailyId, isNotNull);
        expect(shift.businessDate, OperationFlowService.businessDateOf());
      },
    );

    test('closeSession rejects closing a shift from another cashier', () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxToday(db);
      final shiftId = await _insertOpenShift(
        db,
        userId: 2,
        userName: 'Cashier 2',
        cashboxId: cashboxId,
      );

      await SessionManager.login(
        userId: 1,
        username: 'admin',
        displayName: 'Admin',
        role: 'admin',
      );

      final summary = CashSummaryModel.empty(openingAmount: 100);
      await expectLater(
        () => CashRepository.closeSession(
          sessionId: shiftId,
          closingAmount: 100,
          note: 'test close',
          summary: summary,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('pertenece a otro cajero'),
          ),
        ),
      );
    });

    test(
      'closeSession persists CLOSED state and timestamps when valid',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final shiftId = await _insertOpenShift(
          db,
          userId: 1,
          userName: 'Admin',
          cashboxId: cashboxId,
        );

        final summary = CashSummaryModel.empty(openingAmount: 100);
        await CashRepository.closeSession(
          sessionId: shiftId,
          closingAmount: 120,
          note: 'cierre correcto',
          summary: summary,
          expectedUserId: 1,
          expectedCashboxDailyId: cashboxId,
        );

        final row = await db.query(
          DbTables.cashSessions,
          where: 'id = ?',
          whereArgs: [shiftId],
          limit: 1,
        );

        expect(row, isNotEmpty);
        expect(row.first['status'], 'CLOSED');
        expect(row.first['closed_at_ms'], isNotNull);
        expect((row.first['closing_amount'] as num?)?.toDouble(), 120);
        expect((row.first['expected_cash'] as num?)?.toDouble(), 100);
        expect((row.first['difference'] as num?)?.toDouble(), 20);
      },
    );

    test(
      'closeSession deletes pending POS tickets for the closing cashier',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final shiftId = await _insertOpenShift(
          db,
          userId: 1,
          userName: 'Admin',
          cashboxId: cashboxId,
        );

        // Ticket pendiente del usuario 1 (debe eliminarse)
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert(DbTables.posTickets, {
          'ticket_name': 'T1',
          'user_id': 1,
          'client_id': null,
          'itbis_enabled': 1,
          'itbis_rate': 0.18,
          'discount_total': 0.0,
          'created_at_ms': now,
          'updated_at_ms': now,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        // Ticket pendiente de otro usuario (NO debe eliminarse)
        await db.insert(DbTables.posTickets, {
          'ticket_name': 'T2',
          'user_id': 2,
          'client_id': null,
          'itbis_enabled': 1,
          'itbis_rate': 0.18,
          'discount_total': 0.0,
          'created_at_ms': now,
          'updated_at_ms': now,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        final summary = CashSummaryModel.empty(openingAmount: 100);
        await CashRepository.closeSession(
          sessionId: shiftId,
          closingAmount: 100,
          note: 'close',
          summary: summary,
          expectedUserId: 1,
          expectedCashboxDailyId: cashboxId,
        );

        final remaining = await db.query(
          DbTables.posTickets,
          columns: ['ticket_name', 'user_id'],
          orderBy: 'id ASC',
        );

        expect(remaining.length, 1);
        expect(remaining.first['ticket_name'], 'T2');
        expect(remaining.first['user_id'], 2);
      },
    );

    test('closeDailyCashboxToday blocks while there are open shifts', () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxToday(db);
      await _insertOpenShift(
        db,
        userId: 1,
        userName: 'Admin',
        cashboxId: cashboxId,
      );

      await SessionManager.login(
        userId: 1,
        username: 'admin',
        displayName: 'Admin',
        role: 'admin',
      );

      await expectLater(
        () => OperationFlowService.closeDailyCashboxToday(note: 'fin dia'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('existen turnos abiertos'),
          ),
        ),
      );
    });

    test(
      'openDailyCashboxToday allows reopening after close same day',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);

        // Cerrar la caja existente
        await db.update(
          DbTables.cashboxDaily,
          {
            'status': 'CLOSED',
            'closed_at_ms': DateTime.now().millisecondsSinceEpoch,
            'closed_by_user_id': 1,
          },
          where: 'id = ?',
          whereArgs: [cashboxId],
        );

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final reopened = await OperationFlowService.openDailyCashboxToday(
          openingAmount: 50,
          note: 'reopen test',
        );

        expect(reopened.id, cashboxId);
        expect(reopened.isOpen, isTrue);
        expect(reopened.closedAtMs, isNull);
        expect(reopened.closedByUserId, isNull);
        expect(reopened.initialAmount, 50);
      },
    );

    test(
      'openDailyCashboxToday blocks reopening if there is an open shift',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);

        // Cerrar la caja existente
        await db.update(
          DbTables.cashboxDaily,
          {
            'status': 'CLOSED',
            'closed_at_ms': DateTime.now().millisecondsSinceEpoch,
            'closed_by_user_id': 1,
          },
          where: 'id = ?',
          whereArgs: [cashboxId],
        );

        // Simular que existe un turno abierto ligado a esa caja
        await _insertOpenShift(
          db,
          userId: 1,
          userName: 'Admin',
          cashboxId: cashboxId,
        );

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        await expectLater(
          () => OperationFlowService.openDailyCashboxToday(
            openingAmount: 10,
            note: 'reopen blocked',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains(
                'No se puede reabrir la caja mientras existan turnos abiertos',
              ),
            ),
          ),
        );
      },
    );

    test(
      'loadGateState does not force cut just because business_date is yesterday (within 48h)',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        // Insertar un turno abierto con business_date de ayer.
        final yesterday = await _yesterdayBusinessDate();
        await db.insert(DbTables.cashSessions, {
          'opened_by_user_id': 1,
          'user_name': 'Admin',
          'opened_at_ms': DateTime.now().millisecondsSinceEpoch,
          'initial_amount': 0.0,
          'cashbox_daily_id': cashboxId,
          'business_date': yesterday,
          'requires_closure': 0,
          'status': 'OPEN',
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        final gate = await OperationFlowService.loadGateState();
        expect(gate.hasUserShiftOpen, isTrue);
        expect(gate.hasStaleShift, isFalse);
        expect(gate.canOperate, isTrue);
      },
    );

    test(
      'openShiftForCurrentUser allows another user open shift in same cashbox',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);
        await _insertOpenShift(
          db,
          userId: 2,
          userName: 'Cashier 2',
          cashboxId: cashboxId,
        );

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final shift = await OperationFlowService.openShiftForCurrentUser();
        expect(shift.isOpen, isTrue);
        expect(shift.userId, 1);
        expect(shift.cashboxDailyId, cashboxId);
      },
    );

    test(
      'buildDailySummary aggregates sales and movements across sessions',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);
        final businessDate = OperationFlowService.businessDateOf();

        final session1 = await _insertOpenShift(
          db,
          userId: 1,
          userName: 'Admin',
          cashboxId: cashboxId,
          businessDate: businessDate,
        );
        final session2 = await _insertOpenShift(
          db,
          userId: 2,
          userName: 'Cashier 2',
          cashboxId: cashboxId,
          businessDate: businessDate,
        );

        final now = DateTime.now().millisecondsSinceEpoch;
        await db.insert(DbTables.sales, {
          'local_code': 'TEST-SALE-1',
          'kind': 'invoice',
          'status': 'completed',
          'payment_method': 'cash',
          'paid_amount': 50.0,
          'total': 50.0,
          'session_id': session1,
          'created_at_ms': now,
          'updated_at_ms': now,
          'deleted_at_ms': null,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        await db.insert(DbTables.sales, {
          'local_code': 'TEST-SALE-2',
          'kind': 'invoice',
          'status': 'completed',
          'payment_method': 'card',
          'paid_amount': 30.0,
          'total': 30.0,
          'session_id': session2,
          'created_at_ms': now + 1,
          'updated_at_ms': now + 1,
          'deleted_at_ms': null,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        await CashRepository.addMovement(
          sessionId: session1,
          type: 'IN',
          amount: 10.0,
          reason: 'Entrada test',
          userId: 1,
        );
        await CashRepository.addMovement(
          sessionId: session2,
          type: 'OUT',
          amount: 5.0,
          reason: 'Retiro test',
          userId: 2,
        );

        final summary = await CashRepository.buildDailySummary(
          cashboxDailyId: cashboxId,
          businessDate: businessDate,
        );

        expect(summary.openingAmount, 100.0);
        expect(summary.salesCashTotal, 50.0);
        expect(summary.salesCardTotal, 30.0);
        expect(summary.cashInManual, 10.0);
        expect(summary.cashOutManual, 5.0);
        expect(summary.totalTickets, 2);
        expect(summary.expectedCash, 155.0);
      },
    );
  });
}
