import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/tables.dart';
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
    const orphanBusinessDate = '2000-01-01';
    final openedAt = DateTime(2000, 1, 1, 9).millisecondsSinceEpoch;
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
    expect(todayRows, isEmpty);
  });

  test(
    'restaura turno abierto existente de la caja en vez de lanzar conflicto',
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

      expect(session.shiftId, shiftId);
      expect(session.cashId, cashboxId);
      expect(session.userId, 2);
      expect(session.userName, 'Cajero');

      final shifts = await db.query(DbTables.cashSessions);
      expect(shifts, hasLength(1));
      expect(shifts.first['opened_by_user_id'], 2);
      expect(shifts.first['user_name'], 'Cajero');
      expect(shifts.first['status'], 'OPEN');
      expect(shifts.first['closed_at_ms'], isNull);
    },
  );
}
