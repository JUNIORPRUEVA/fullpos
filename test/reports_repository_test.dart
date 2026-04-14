import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/features/cash/data/cash_repository.dart';
import 'package:fullpos/features/cash/data/operation_flow_service.dart';
import 'package:fullpos/features/reports/data/reports_repository.dart';
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
}

Future<void> _cleanReportTables(Database db) async {
  await db.delete(DbTables.cashMovements);
  await db.delete(DbTables.returnItems);
  await db.delete(DbTables.returns);
  await db.delete(DbTables.facturaElectronica);
  await db.delete(DbTables.saleItems);
  await db.delete(DbTables.sales);
  await db.delete(DbTables.cashSessions);
  await db.delete(DbTables.cashboxDaily);
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

Future<int> _insertOpenShift(Database db, {required int cashboxId}) async {
  return db.insert(DbTables.cashSessions, {
    'opened_by_user_id': 1,
    'user_name': 'Admin',
    'opened_at_ms': DateTime.now().millisecondsSinceEpoch,
    'initial_amount': 0.0,
    'cashbox_daily_id': cashboxId,
    'business_date': OperationFlowService.businessDateOf(),
    'requires_closure': 0,
    'status': 'OPEN',
  }, conflictAlgorithm: ConflictAlgorithm.abort);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUpAll(() async {
    DbInit.ensureInitialized();
    docsDir = await Directory.systemTemp.createTemp('fullpos_reports_test_');
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
    await _cleanReportTables(db);
    await _seedUsers(db);
  });

  test(
    'getKpis keeps sales real and discounts filtered expenses from net profit',
    () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxTodayWithAmount(db, 500.0);
      final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);
      final now = DateTime.now().millisecondsSinceEpoch;

      await CashRepository.addMovement(
        sessionId: shiftId,
        type: 'IN',
        amount: 80.0,
        reason: 'Entrada manual test',
        userId: 1,
      );

      await CashRepository.addMovement(
        sessionId: shiftId,
        type: 'OUT',
        amount: 15.0,
        reason: 'Gasto manual test',
        userId: 1,
      );

      await SalesRepository.createSale(
        localCode: 'V-REPORT-KPI-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-REPORT-1',
            'product_name_snapshot': 'Producto reporte',
            'qty': 1.0,
            'unit_price': 100.0,
            'purchase_price_snapshot': 40.0,
            'discount_line': 0.0,
            'total_line': 100.0,
          },
        ],
        itbisEnabled: false,
        subtotalOverride: 100.0,
        itbisAmountOverride: 0.0,
        totalOverride: 100.0,
        paymentMethod: 'cash',
        paymentCashAmount: 100.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 100.0,
        changeAmount: 0.0,
      );

      final kpis = await ReportsRepository.getKpis(
        startMs: now - 60000,
        endMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );

      expect(kpis.totalSales, 100.0);
      expect(kpis.totalProfit, 60.0);
      expect(kpis.netProfit, 45.0);
      expect(kpis.salesCount, 1);
      expect(kpis.cashIncome, 80.0);
      expect(kpis.cashExpense, 15.0);
    },
  );

  test(
    'getKpis uses final invoice totals for sales while keeping item profit basis',
    () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
      final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);
      final now = DateTime.now().millisecondsSinceEpoch;

      await SalesRepository.createSale(
        localCode: 'V-REPORT-KPI-FINAL-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-REPORT-FINAL-1',
            'product_name_snapshot': 'Producto A',
            'qty': 1.0,
            'unit_price': 420.0,
            'purchase_price_snapshot': 120.0,
            'discount_line': 0.0,
            'total_line': 420.0,
          },
          {
            'product_code_snapshot': 'P-REPORT-FINAL-2',
            'product_name_snapshot': 'Producto B',
            'qty': 1.0,
            'unit_price': 250.0,
            'purchase_price_snapshot': 70.0,
            'discount_line': 200.0,
            'total_line': 50.0,
          },
        ],
        itbisEnabled: true,
        discountTotal: 400.0,
        subtotalOverride: 270.0,
        itbisAmountOverride: 48.6,
        totalOverride: 318.6,
        paymentMethod: 'cash',
        paymentCashAmount: 318.6,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 318.6,
        changeAmount: 0.0,
      );

      final kpis = await ReportsRepository.getKpis(
        startMs: now - 60000,
        endMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );

      expect(kpis.totalSales, 318.6);
      expect(kpis.avgTicket, 318.6);
      expect(kpis.totalProfit, 280.0);
      expect(kpis.salesCount, 1);
    },
  );

  test(
    'profit series discounts daily expenses and keeps expense-only days negative',
    () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
      final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);

      final dayOne = DateTime(2026, 3, 20, 10).millisecondsSinceEpoch;
      final dayTwo = DateTime(2026, 3, 21, 10).millisecondsSinceEpoch;

      final saleId = await SalesRepository.createSale(
        localCode: 'V-REPORT-PROFIT-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-PROFIT-1',
            'product_name_snapshot': 'Producto utilidad',
            'qty': 1.0,
            'unit_price': 120.0,
            'purchase_price_snapshot': 50.0,
            'discount_line': 0.0,
            'total_line': 120.0,
          },
        ],
        itbisEnabled: false,
        subtotalOverride: 120.0,
        itbisAmountOverride: 0.0,
        totalOverride: 120.0,
        paymentMethod: 'cash',
        paymentCashAmount: 120.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 120.0,
        changeAmount: 0.0,
      );

      await db.update(
        DbTables.sales,
        {'created_at_ms': dayOne, 'updated_at_ms': dayOne},
        where: 'id = ?',
        whereArgs: [saleId],
      );
      await db.update(
        DbTables.saleItems,
        {'created_at_ms': dayOne},
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      await db.insert(DbTables.cashMovements, {
        'session_id': shiftId,
        'type': 'OUT',
        'amount': 10.0,
        'reason': 'Gasto dia 1',
        'user_id': 1,
        'created_at_ms': dayOne,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await db.insert(DbTables.cashMovements, {
        'session_id': shiftId,
        'type': 'OUT',
        'amount': 30.0,
        'reason': 'Gasto dia 2',
        'user_id': 1,
        'created_at_ms': dayTwo,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final series = await ReportsRepository.getProfitSeries(
        startMs: DateTime(2026, 3, 20).millisecondsSinceEpoch,
        endMs: DateTime(2026, 3, 21, 23, 59, 59).millisecondsSinceEpoch,
      );

      final byDate = {for (final point in series) point.label: point.value};
      expect(byDate['2026-03-20'], closeTo(60.0, 0.001));
      expect(byDate['2026-03-21'], closeTo(-30.0, 0.001));
    },
  );

  test(
    'payment method distribution splits mixed sales using stored real amounts and offsets returns proportionally',
    () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
      final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);
      final now = DateTime.now().millisecondsSinceEpoch;

      final mixedSaleId = await SalesRepository.createSale(
        localCode: 'V-REPORT-MIXED-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-MIX-1',
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

      await SalesRepository.createSale(
        localCode: 'V-REPORT-TRANSFER-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-TRF-1',
            'product_name_snapshot': 'Producto transferencia',
            'qty': 1.0,
            'unit_price': 25.0,
            'purchase_price_snapshot': 10.0,
            'discount_line': 0.0,
            'total_line': 25.0,
          },
        ],
        itbisEnabled: false,
        subtotalOverride: 25.0,
        itbisAmountOverride: 0.0,
        totalOverride: 25.0,
        paymentMethod: 'transfer',
        paymentCashAmount: 0.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 25.0,
        sessionId: shiftId,
        paidAmount: 25.0,
        changeAmount: 0.0,
      );

      final returnSaleId = await db.insert(DbTables.sales, {
        'local_code': 'R-REPORT-MIXED-001',
        'kind': 'return',
        'status': 'completed',
        'payment_method': 'cash',
        'itbis_enabled': 0,
        'itbis_rate': 0.0,
        'discount_total': 0.0,
        'subtotal': -50.0,
        'itbis_amount': 0.0,
        'total': -50.0,
        'payment_cash_amount': 0.0,
        'payment_card_amount': 0.0,
        'payment_transfer_amount': 0.0,
        'paid_amount': 0.0,
        'change_amount': 0.0,
        'electronic_invoice_enabled': 0,
        'session_id': shiftId,
        'created_at_ms': now + 1,
        'updated_at_ms': now + 1,
        'deleted_at_ms': null,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await db.insert(DbTables.returns, {
        'original_sale_id': mixedSaleId,
        'return_sale_id': returnSaleId,
        'note': 'devolucion parcial',
        'created_at_ms': now + 1,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final distribution = await ReportsRepository.getPaymentMethodDistribution(
        startMs: now - 60000,
        endMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );

      final byMethod = {for (final entry in distribution) entry.method: entry};

      expect(byMethod['Efectivo']?.amount, closeTo(20.0, 0.001));
      expect(byMethod['Tarjeta']?.amount, closeTo(30.0, 0.001));
      expect(byMethod['Transferencia']?.amount, closeTo(25.0, 0.001));
      expect(byMethod['Efectivo']?.count, 1);
      expect(byMethod['Tarjeta']?.count, 1);
      expect(byMethod['Transferencia']?.count, 1);
      expect(byMethod.containsKey('Mixto'), isFalse);
    },
  );

  test(
    'client sales summaries and client sales list respect customer and date range filters',
    () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
      final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);
      final baseTime = DateTime(2026, 3, 22, 10).millisecondsSinceEpoch;

      await db.insert(DbTables.clients, {
        'id': 101,
        'nombre': 'Cliente Uno',
        'telefono': '8090000001',
        'direccion': 'Zona 1',
        'rnc': null,
        'cedula': null,
        'is_active': 1,
        'has_credit': 1,
        'created_at_ms': baseTime,
        'updated_at_ms': baseTime,
        'deleted_at_ms': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert(DbTables.clients, {
        'id': 102,
        'nombre': 'Cliente Dos',
        'telefono': '8090000002',
        'direccion': 'Zona 2',
        'rnc': null,
        'cedula': null,
        'is_active': 1,
        'has_credit': 0,
        'created_at_ms': baseTime,
        'updated_at_ms': baseTime,
        'deleted_at_ms': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final saleClientOne = await SalesRepository.createSale(
        localCode: 'V-CLIENT-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-CLIENT-1',
            'product_name_snapshot': 'Producto cliente 1',
            'qty': 1.0,
            'unit_price': 80.0,
            'purchase_price_snapshot': 30.0,
            'discount_line': 0.0,
            'total_line': 80.0,
          },
        ],
        customerId: 101,
        customerName: 'Cliente Uno',
        itbisEnabled: false,
        subtotalOverride: 80.0,
        itbisAmountOverride: 0.0,
        totalOverride: 80.0,
        paymentMethod: 'credit',
        paymentCashAmount: 0.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 0.0,
        changeAmount: 0.0,
      );

      final saleClientTwo = await SalesRepository.createSale(
        localCode: 'V-CLIENT-002',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-CLIENT-2',
            'product_name_snapshot': 'Producto cliente 2',
            'qty': 1.0,
            'unit_price': 40.0,
            'purchase_price_snapshot': 10.0,
            'discount_line': 0.0,
            'total_line': 40.0,
          },
        ],
        customerId: 102,
        customerName: 'Cliente Dos',
        itbisEnabled: false,
        subtotalOverride: 40.0,
        itbisAmountOverride: 0.0,
        totalOverride: 40.0,
        paymentMethod: 'cash',
        paymentCashAmount: 40.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 40.0,
        changeAmount: 0.0,
      );

      await db.update(
        DbTables.sales,
        {'created_at_ms': baseTime, 'updated_at_ms': baseTime},
        where: 'id = ?',
        whereArgs: [saleClientOne],
      );
      await db.update(
        DbTables.sales,
        {
          'created_at_ms': baseTime + const Duration(days: 1).inMilliseconds,
          'updated_at_ms': baseTime + const Duration(days: 1).inMilliseconds,
        },
        where: 'id = ?',
        whereArgs: [saleClientTwo],
      );

      final summaries = await ReportsRepository.getClientSalesSummaries(
        startMs: DateTime(2026, 3, 22).millisecondsSinceEpoch,
        endMs: DateTime(2026, 3, 23, 23, 59, 59).millisecondsSinceEpoch,
      );

      expect(summaries.length, 2);
      expect(summaries.first.clientName, 'Cliente Uno');
      expect(summaries.first.totalSales, 80.0);
      expect(summaries.first.totalCredit, 80.0);
      expect(summaries.first.salesCount, 1);

      final clientOneSales = await ReportsRepository.getSalesListByClient(
        clientId: 101,
        startMs: DateTime(2026, 3, 22).millisecondsSinceEpoch,
        endMs: DateTime(2026, 3, 22, 23, 59, 59).millisecondsSinceEpoch,
      );

      expect(clientOneSales.length, 1);
      expect(clientOneSales.first.localCode, 'V-CLIENT-001');
      expect(clientOneSales.first.customerId, 101);

      final clientTwoSalesOutOfRange =
          await ReportsRepository.getSalesListByClient(
            clientId: 102,
            startMs: DateTime(2026, 3, 22).millisecondsSinceEpoch,
            endMs: DateTime(2026, 3, 22, 23, 59, 59).millisecondsSinceEpoch,
          );

      expect(clientTwoSalesOutOfRange, isEmpty);
    },
  );

  test(
    'client sales summaries net credit returns and do not split same client by snapshot name',
    () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
      final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);
      final now = DateTime(2026, 3, 24, 10).millisecondsSinceEpoch;

      await db.insert(DbTables.clients, {
        'id': 201,
        'nombre': 'Cliente Consolidado',
        'telefono': '8090000201',
        'direccion': 'Zona 201',
        'rnc': null,
        'cedula': null,
        'is_active': 1,
        'has_credit': 1,
        'created_at_ms': now,
        'updated_at_ms': now,
        'deleted_at_ms': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final originalSaleId = await SalesRepository.createSale(
        localCode: 'V-CLIENT-NET-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-NET-1',
            'product_name_snapshot': 'Producto neto',
            'qty': 1.0,
            'unit_price': 100.0,
            'purchase_price_snapshot': 40.0,
            'discount_line': 0.0,
            'total_line': 100.0,
          },
        ],
        customerId: 201,
        customerName: 'Cliente Nombre Viejo',
        itbisEnabled: false,
        subtotalOverride: 100.0,
        itbisAmountOverride: 0.0,
        totalOverride: 100.0,
        paymentMethod: 'credit',
        paymentCashAmount: 0.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 0.0,
        changeAmount: 0.0,
      );

      await db.update(
        DbTables.sales,
        {'created_at_ms': now, 'updated_at_ms': now},
        where: 'id = ?',
        whereArgs: [originalSaleId],
      );

      final returnSaleId = await db.insert(DbTables.sales, {
        'local_code': 'DEV-CLIENT-NET-001',
        'kind': 'return',
        'status': 'completed',
        'customer_id': 201,
        'customer_name_snapshot': 'Cliente Nombre Nuevo',
        'itbis_enabled': 0,
        'itbis_rate': 0.0,
        'discount_total': 0.0,
        'subtotal': -25.0,
        'itbis_amount': 0.0,
        'total': -25.0,
        'payment_method': 'return',
        'paid_amount': 0.0,
        'change_amount': 0.0,
        'electronic_invoice_enabled': 0,
        'session_id': shiftId,
        'created_at_ms': now + 1,
        'updated_at_ms': now + 1,
        'deleted_at_ms': null,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final returnId = await db.insert(DbTables.returns, {
        'original_sale_id': originalSaleId,
        'return_sale_id': returnSaleId,
        'note': 'devolucion credito',
        'created_at_ms': now + 1,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await db.insert(DbTables.returnItems, {
        'return_id': returnId,
        'sale_item_id': null,
        'product_id': null,
        'description': 'Producto neto',
        'qty': 1.0,
        'price': 25.0,
        'total': 25.0,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final summaries = await ReportsRepository.getClientSalesSummaries(
        startMs: now - 1000,
        endMs: now + 60000,
      );
      final topClients = await ReportsRepository.getTopClients(
        startMs: now - 1000,
        endMs: now + 60000,
      );

      expect(summaries.length, 1);
      expect(summaries.first.clientName, 'Cliente Consolidado');
      expect(summaries.first.totalSales, 75.0);
      expect(summaries.first.totalCredit, 75.0);
      expect(topClients.length, 1);
      expect(topClients.first.clientName, 'Cliente Consolidado');
      expect(topClients.first.totalSpent, 75.0);
    },
  );

  test(
    'top products consolidate renamed snapshots and resolved product ids',
    () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
      final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);
      final now = DateTime(2026, 3, 24, 12).millisecondsSinceEpoch;

      await db.insert(DbTables.products, {
        'id': 401,
        'code': 'P-TOP-401',
        'name': 'Producto Maestro',
        'category_id': null,
        'supplier_id': null,
        'purchase_price': 30.0,
        'sale_price': 100.0,
        'stock': 10.0,
        'reserved_stock': 0.0,
        'stock_min': 0.0,
        'is_active': 1,
        'deleted_at_ms': null,
        'created_at_ms': now,
        'updated_at_ms': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final firstSaleId = await SalesRepository.createSale(
        localCode: 'V-TOP-001',
        kind: 'invoice',
        items: [
          {
            'product_id': 401,
            'product_code_snapshot': 'P-TOP-401',
            'product_name_snapshot': 'Producto Version Antigua',
            'qty': 1.0,
            'unit_price': 100.0,
            'purchase_price_snapshot': 30.0,
            'discount_line': 0.0,
            'total_line': 100.0,
          },
        ],
        itbisEnabled: false,
        subtotalOverride: 100.0,
        itbisAmountOverride: 0.0,
        totalOverride: 100.0,
        paymentMethod: 'cash',
        paymentCashAmount: 100.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 100.0,
        changeAmount: 0.0,
      );

      final secondSaleId = await SalesRepository.createSale(
        localCode: 'V-TOP-002',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'P-TOP-401',
            'product_name_snapshot': 'Producto Renombrado en Snapshot',
            'qty': 1.0,
            'unit_price': 50.0,
            'purchase_price_snapshot': 30.0,
            'discount_line': 0.0,
            'total_line': 50.0,
          },
        ],
        itbisEnabled: false,
        subtotalOverride: 50.0,
        itbisAmountOverride: 0.0,
        totalOverride: 50.0,
        paymentMethod: 'cash',
        paymentCashAmount: 50.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 50.0,
        changeAmount: 0.0,
      );

      await db.update(
        DbTables.sales,
        {'created_at_ms': now, 'updated_at_ms': now},
        where: 'id IN (?, ?)',
        whereArgs: [firstSaleId, secondSaleId],
      );

      final topProducts = await ReportsRepository.getTopProducts(
        startMs: now - 1000,
        endMs: now + 60000,
      );

      expect(topProducts.length, 1);
      expect(topProducts.first.productId, 401);
      expect(topProducts.first.productName, 'Producto Maestro');
      expect(topProducts.first.totalSales, 150.0);
      expect(topProducts.first.totalQty, 2.0);
    },
  );

  test(
    'top products net returns for the same resolved product without splitting rows',
    () async {
      final db = await AppDb.database;
      final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
      final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);
      final now = DateTime(2026, 3, 24, 13).millisecondsSinceEpoch;

      await db.insert(DbTables.products, {
        'id': 402,
        'code': 'P-TOP-402',
        'name': 'Producto Retornable',
        'category_id': null,
        'supplier_id': null,
        'purchase_price': 25.0,
        'sale_price': 80.0,
        'stock': 10.0,
        'reserved_stock': 0.0,
        'stock_min': 0.0,
        'is_active': 1,
        'deleted_at_ms': null,
        'created_at_ms': now,
        'updated_at_ms': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final saleId = await SalesRepository.createSale(
        localCode: 'V-TOP-RET-001',
        kind: 'invoice',
        items: [
          {
            'product_id': 402,
            'product_code_snapshot': 'P-TOP-402',
            'product_name_snapshot': 'Producto Snapshot Venta',
            'qty': 2.0,
            'unit_price': 80.0,
            'purchase_price_snapshot': 25.0,
            'discount_line': 0.0,
            'total_line': 160.0,
          },
        ],
        itbisEnabled: false,
        subtotalOverride: 160.0,
        itbisAmountOverride: 0.0,
        totalOverride: 160.0,
        paymentMethod: 'cash',
        paymentCashAmount: 160.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        sessionId: shiftId,
        paidAmount: 160.0,
        changeAmount: 0.0,
      );

      await db.update(
        DbTables.sales,
        {'created_at_ms': now, 'updated_at_ms': now},
        where: 'id = ?',
        whereArgs: [saleId],
      );

      final saleItems = await db.query(
        DbTables.saleItems,
        columns: ['id'],
        where: 'sale_id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      final saleItemId = saleItems.first['id'] as int;

      final returnSaleId = await db.insert(DbTables.sales, {
        'local_code': 'DEV-TOP-RET-001',
        'kind': 'return',
        'status': 'completed',
        'itbis_enabled': 0,
        'itbis_rate': 0.0,
        'discount_total': 0.0,
        'subtotal': -80.0,
        'itbis_amount': 0.0,
        'total': -80.0,
        'payment_method': 'return',
        'paid_amount': 0.0,
        'change_amount': 0.0,
        'electronic_invoice_enabled': 0,
        'session_id': shiftId,
        'created_at_ms': now + 1,
        'updated_at_ms': now + 1,
        'deleted_at_ms': null,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final returnId = await db.insert(DbTables.returns, {
        'original_sale_id': saleId,
        'return_sale_id': returnSaleId,
        'note': 'devolucion parcial producto top',
        'created_at_ms': now + 1,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await db.insert(DbTables.returnItems, {
        'return_id': returnId,
        'sale_item_id': saleItemId,
        'product_id': null,
        'description': 'Producto Snapshot Devolucion',
        'qty': 1.0,
        'price': 80.0,
        'total': 80.0,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final topProducts = await ReportsRepository.getTopProducts(
        startMs: now - 1000,
        endMs: now + 60000,
      );

      expect(topProducts.length, 1);
      expect(topProducts.first.productId, 402);
      expect(topProducts.first.productName, 'Producto Retornable');
      expect(topProducts.first.totalSales, 80.0);
      expect(topProducts.first.totalQty, 1.0);
      expect(topProducts.first.totalProfit, 55.0);
    },
  );

  test('customer purchase summary includes paid invoices', () async {
    final db = await AppDb.database;
    final cashboxId = await _insertCashboxTodayWithAmount(db, 0.0);
    final shiftId = await _insertOpenShift(db, cashboxId: cashboxId);
    final now = DateTime(2026, 3, 25, 10).millisecondsSinceEpoch;

    await db.insert(DbTables.clients, {
      'id': 301,
      'nombre': 'Cliente Paid',
      'telefono': '8090000301',
      'direccion': 'Zona paid',
      'rnc': null,
      'cedula': null,
      'is_active': 1,
      'has_credit': 0,
      'created_at_ms': now,
      'updated_at_ms': now,
      'deleted_at_ms': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final saleId = await SalesRepository.createSale(
      localCode: 'V-PAID-001',
      kind: 'invoice',
      items: [
        {
          'product_code_snapshot': 'P-PAID-1',
          'product_name_snapshot': 'Producto paid',
          'qty': 1.0,
          'unit_price': 55.0,
          'purchase_price_snapshot': 20.0,
          'discount_line': 0.0,
          'total_line': 55.0,
        },
      ],
      customerId: 301,
      customerName: 'Cliente Paid',
      itbisEnabled: false,
      subtotalOverride: 55.0,
      itbisAmountOverride: 0.0,
      totalOverride: 55.0,
      paymentMethod: 'cash',
      paymentCashAmount: 55.0,
      paymentCardAmount: 0.0,
      paymentTransferAmount: 0.0,
      sessionId: shiftId,
      paidAmount: 55.0,
      changeAmount: 0.0,
    );

    await db.update(
      DbTables.sales,
      {'status': 'PAID', 'created_at_ms': now, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [saleId],
    );

    final summary = await SalesRepository.getCustomerPurchaseSummary(301);

    expect(summary['count'], 1);
    expect(summary['total'], 55.0);
    expect(summary['lastAtMs'], now);
  });
}
