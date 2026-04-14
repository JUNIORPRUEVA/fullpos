import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/features/cash/data/cash_movement_model.dart';
import 'package:fullpos/features/cash/data/cash_repository.dart';
import 'package:fullpos/features/cash/data/cash_summary_model.dart';
import 'package:fullpos/features/cash/data/operation_flow_service.dart';
import 'package:fullpos/features/sales/data/sales_repository.dart';
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
  await db.delete(DbTables.returnItems);
  await db.delete(DbTables.returns);
  await db.delete(DbTables.saleItems);
  await db.delete(DbTables.creditPayments);
  await db.delete(DbTables.layawayPayments);
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
    'current_amount': 100.0,
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
    'current_amount': amount,
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

  group('Single-session hardening', () {
    test(
      'login with closed session requires starting a new active session',
      () async {
        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        expect(await OperationFlowService.loadActiveSession(), isNull);

        final activeSession = await OperationFlowService.startActiveSession(
          openingAmount: 125.0,
          note: 'login bootstrap',
        );

        expect(activeSession.userId, 1);
        expect(activeSession.isOpen, isTrue);
        expect(await OperationFlowService.loadActiveSession(), isNotNull);
      },
    );

    test(
      'login with open session restores direct access immediately',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);
        final shiftId = await _insertOpenShift(
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

        final gate = await OperationFlowService.loadGateState();
        final activeSession = await OperationFlowService.loadActiveSession();

        expect(gate.canOperate, isTrue);
        expect(activeSession, isNotNull);
        expect(activeSession?.shiftId, shiftId);
        expect(activeSession?.cashId, cashboxId);
      },
    );

    test(
      'recovery after crash restores the same active session on next login',
      () async {
        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final started = await OperationFlowService.startActiveSession(
          openingAmount: 200.0,
          note: 'session before crash',
        );

        await SessionManager.logout();
        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final restored = await OperationFlowService.loadActiveSession();
        expect(restored, isNotNull);
        expect(restored?.shiftId, started.shiftId);
        expect(restored?.cashId, started.cashId);
      },
    );

    test(
      'mixed payment splits cash and card correctly in cash summary',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
        final shiftId = await _insertOpenShift(
          db,
          userId: 1,
          userName: 'Admin',
          cashboxId: cashboxId,
        );

        await SalesRepository.createSale(
          localCode: 'V-MIXED-TEST-001',
          kind: 'invoice',
          items: [
            {
              'product_code_snapshot': 'P-001',
              'product_name_snapshot': 'Producto mixto',
              'qty': 1.0,
              'unit_price': 100.0,
              'purchase_price_snapshot': 50.0,
              'discount_line': 0.0,
              'total_line': 100.0,
            },
          ],
          itbisEnabled: false,
          subtotalOverride: 100.0,
          itbisAmountOverride: 0.0,
          totalOverride: 100.0,
          paymentMethod: 'mixed',
          paymentCashAmount: 40.0,
          paymentCardAmount: 60.0,
          paymentTransferAmount: 0.0,
          sessionId: shiftId,
          paidAmount: 100.0,
          changeAmount: 0.0,
        );

        final CashSummaryModel summary = await CashRepository.buildSummary(
          sessionId: shiftId,
        );

        expect(summary.salesCashTotal, 40.0);
        expect(summary.salesCardTotal, 60.0);
        expect(summary.salesTransferTotal, 0.0);
        expect(summary.expectedCash, 40.0);
      },
    );

    test(
      'gate marks stale shift but keeps the active session restorable',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final nowMs = DateTime.now().millisecondsSinceEpoch;

        // Caso 1: sesión abierta hace 47h -> debe permitir operar.
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

        // Caso 2: sesión abierta hace 49h -> se marca stale, pero sigue siendo
        // una sesión activa restorable tras reinicio/corte eléctrico.
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
        expect(gate.canOperate, isTrue);
      },
    );

    test(
      'getOpenSession ignores a legacy-closed session (status OPEN but closed_at_ms set)',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final legacyId = await db.insert(DbTables.cashSessions, {
          'opened_by_user_id': 1,
          'user_name': 'Admin',
          'opened_at_ms': nowMs - 10 * 1000,
          'initial_amount': 100.0,
          'cashbox_daily_id': cashboxId,
          'business_date': OperationFlowService.businessDateOf(),
          'requires_closure': 0,
          'status': 'OPEN',
          'closed_at_ms': nowMs - 5 * 1000,
          'closing_amount': 250.0,
          'expected_cash': 250.0,
          'difference': 0.0,
          'note': 'legacy',
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        final open = await CashRepository.getOpenSession(userId: 1);
        expect(open, isNull);

        final newShift = await OperationFlowService.openShiftForCurrentUser(
          openingAmount: 0,
        );
        expect(newShift.id, isNot(legacyId));
      },
    );

    test(
      'closing the active session closes cash and the next login requires a new opening amount',
      () async {
        final db = await AppDb.database;
        await _insertCashboxTodayWithAmount(db, 3000.0);

        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );

        final activeSession = await OperationFlowService.startActiveSession(
          openingAmount: 3000.0,
          note: 'apertura inicial',
        );
        final shift1 = await CashRepository.getSessionById(
          activeSession.shiftId,
        );
        expect(shift1, isNotNull);
        expect(shift1?.openingAmount, 3000.0);

        await OperationFlowService.closeActiveSession(
          sessionId: activeSession.shiftId,
          closingAmount: 3100.0,
          note: 'cierre 1',
        );

        expect(await OperationFlowService.getOpenDailyCashboxToday(), isNull);

        final reopenedSession = await OperationFlowService.startActiveSession(
          openingAmount: 3000.0,
          note: 'reapertura',
        );
        final shift2 = await CashRepository.getSessionById(
          reopenedSession.shiftId,
        );
        expect(shift2, isNotNull);
        expect(shift2?.openingAmount, 3000.0);
      },
    );

    test(
      'closeSession can persist the daily cashbox closure metadata',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxTodayWithAmount(db, 1500.0);

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

        await CashRepository.closeSession(
          sessionId: shiftId,
          closingAmount: 1500.0,
          note: 'cierre automatico caja',
          summary: CashSummaryModel.empty(openingAmount: 1500.0),
          expectedUserId: 1,
          expectedCashboxDailyId: cashboxId,
          closeCashboxDaily: true,
          cashboxCloseNote: 'cierre automatico caja',
          cashboxClosedByUserId: 1,
        );

        final cashboxRows = await db.query(
          DbTables.cashboxDaily,
          where: 'id = ?',
          whereArgs: [cashboxId],
          limit: 1,
        );

        expect(cashboxRows, isNotEmpty);
        expect(cashboxRows.first['status'], 'CLOSED');
        expect(cashboxRows.first['closed_at_ms'], isNotNull);
        expect(cashboxRows.first['closed_by_user_id'], 1);
        expect(cashboxRows.first['note'], 'cierre automatico caja');
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
      'closeSession bumps daily cashbox amount by net CASH sales and keeps it OPEN',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxTodayWithAmount(db, 1000.0);

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

        final summary = CashSummaryModel(
          openingAmount: 1000.0,
          totalSales: 4500.0,
          totalExpenses: 0.0,
          totalWithdrawals: 0.0,
          cashInManual: 0.0,
          cashOutManual: 0.0,
          creditAbonos: 0.0,
          layawayAbonos: 0.0,
          salesCashTotal: 4500.0,
          salesCardTotal: 2000.0,
          salesTransferTotal: 0.0,
          salesCreditTotal: 0.0,
          refundsCash: 0.0,
          expectedCash: 5500.0,
          totalTickets: 1,
          totalRefunds: 0,
        );

        await CashRepository.closeSession(
          sessionId: shiftId,
          closingAmount: 5500.0,
          note: 'corte',
          summary: summary,
          expectedUserId: 1,
          expectedCashboxDailyId: cashboxId,
        );

        final cashboxRow = await db.query(
          DbTables.cashboxDaily,
          where: 'id = ?',
          whereArgs: [cashboxId],
          limit: 1,
        );

        expect(cashboxRow, isNotEmpty);
        expect(cashboxRow.first['status'], 'OPEN');
        expect(
          (cashboxRow.first['initial_amount'] as num?)?.toDouble(),
          1000.0,
        );
        expect(
          (cashboxRow.first['current_amount'] as num?)?.toDouble(),
          5500.0,
        );
      },
    );

    test(
      'after closing shift, next cashier opening shift sees updated cashbox current amount',
      () async {
        final db = await AppDb.database;
        await _insertCashboxTodayWithAmount(db, 2000.0);

        // Cajero 1 abre turno (0 -> usa monto actual de caja diaria)
        await SessionManager.login(
          userId: 1,
          username: 'admin',
          displayName: 'Admin',
          role: 'admin',
        );
        final shift1 = await OperationFlowService.openShiftForCurrentUser(
          openingAmount: 0,
        );
        expect(shift1.openingAmount, 2000.0);

        // Cierra turno sumando ventas en efectivo 1000 (neto)
        final summary = CashSummaryModel(
          openingAmount: 2000.0,
          totalSales: 1000.0,
          totalExpenses: 0.0,
          totalWithdrawals: 0.0,
          cashInManual: 0.0,
          cashOutManual: 0.0,
          creditAbonos: 0.0,
          layawayAbonos: 0.0,
          salesCashTotal: 1000.0,
          salesCardTotal: 0.0,
          salesTransferTotal: 0.0,
          salesCreditTotal: 0.0,
          refundsCash: 0.0,
          expectedCash: 3000.0,
          totalTickets: 1,
          totalRefunds: 0,
        );
        await CashRepository.closeSession(
          sessionId: shift1.id!,
          closingAmount: 3000.0,
          note: 'corte',
          summary: summary,
          expectedUserId: 1,
          expectedCashboxDailyId: shift1.cashboxDailyId,
        );

        await SessionManager.logout();

        // Cajero 2 abre turno (0 -> debe ver 3000)
        await SessionManager.login(
          userId: 2,
          username: 'cashier2',
          displayName: 'Cashier 2',
          role: 'cashier',
        );
        final shift2 = await OperationFlowService.openShiftForCurrentUser(
          openingAmount: 0,
        );
        expect(shift2.openingAmount, 3000.0);
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
      'openShiftForCurrentUser rejects another user opening a second active session in the same cashbox',
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

        await expectLater(
          OperationFlowService.openShiftForCurrentUser(),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('sesión activa'),
            ),
          ),
        );
      },
    );

    test(
      'buildDailySummary aggregates sales and movements across sessions',
      () async {
        final db = await AppDb.database;
        final cashboxId = await _insertCashboxToday(db);
        final businessDate = OperationFlowService.businessDateOf();
        final now = DateTime.now().millisecondsSinceEpoch;

        final session1 = await _insertOpenShift(
          db,
          userId: 1,
          userName: 'Admin',
          cashboxId: cashboxId,
          businessDate: businessDate,
        );
        await CashRepository.addMovement(
          sessionId: session1,
          type: 'IN',
          amount: 10.0,
          reason: 'Entrada test',
          userId: 1,
        );
        await db.update(
          DbTables.cashSessions,
          {
            'status': 'CLOSED',
            'closed_at_ms': now,
            'closing_amount': 50.0,
            'expected_cash': 50.0,
            'difference': 0.0,
          },
          where: 'id = ?',
          whereArgs: [session1],
        );
        final session2 = await _insertOpenShift(
          db,
          userId: 2,
          userName: 'Cashier 2',
          cashboxId: cashboxId,
          businessDate: businessDate,
        );

        await db.insert(DbTables.sales, {
          'local_code': 'TEST-SALE-1',
          'kind': 'invoice',
          'status': 'completed',
          'payment_method': 'cash',
          // Cliente entrega más efectivo y se devuelve cambio/devuelta.
          // Para caja debe contar solo el TOTAL vendido, no el efectivo recibido.
          'paid_amount': 60.0,
          'change_amount': 10.0,
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
          sessionId: session2,
          type: 'OUT',
          amount: 5.0,
          reason: 'Retiro test',
          userId: 2,
          movementType: CashMovementAccountingType.ownerDraw,
          affectsProfit: false,
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
        expect(summary.totalExpenses, 0.0);
        expect(summary.totalWithdrawals, 5.0);
        expect(summary.totalTickets, 2);
        expect(summary.expectedCash, 145.0);
      },
    );
  });
}
