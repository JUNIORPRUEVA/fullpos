import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/features/reports/data/report_data_service.dart';
import 'package:fullpos/features/reports/data/reports_repository.dart';
import 'package:fullpos/features/sales/data/returns_repository.dart';
import 'package:fullpos/features/sales/data/sales_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    tempDir = await Directory.systemTemp.createTemp('fullpos_reports_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppDb.resetForTests();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await AppDb.resetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Windows can keep a short-lived handle open from async logging/timers.
      }
    }
  });

  test(
    'devolucion total en el mismo rango deja reportes netos en cero',
    () async {
      final productId = await _insertProduct(stock: 10);
      final saleId = await SalesRepository.saveSaleWithItems(
        localCode: 'V-REP-REFUND',
        kind: 'invoice',
        itbisEnabled: 0,
        itbisRate: 0,
        discountTotal: 0,
        subtotal: 20,
        itbisAmount: 0,
        total: 20,
        paymentMethod: 'cash',
        paymentCashAmount: 20,
        paymentCardAmount: 0,
        paymentTransferAmount: 0,
        paidAmount: 20,
        changeAmount: 0,
        creditInterestRate: 0,
        electronicInvoiceEnabled: 0,
        items: [_saleItem(productId: productId, qty: 2)],
      );
      final saleItemId = await _firstSaleItemId(saleId);

      await ReturnsRepository.createReturn(
        originalSaleId: saleId,
        note: 'devolucion completa para reportes',
        returnItems: [
          {'sale_item_id': saleItemId, 'qty': 2},
        ],
      );

      final db = await AppDb.database;
      final originalRows = await db.query(
        DbTables.sales,
        columns: ['status', 'deleted_at_ms'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      expect(originalRows.first['status'], 'REFUNDED');
      expect(originalRows.first['deleted_at_ms'], isNotNull);

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final kpis = await ReportsRepository.getKpis(
        startMs: start.millisecondsSinceEpoch,
        endMs: end.millisecondsSinceEpoch,
      );
      final report = await ReportDataService.getReportData(
        DateFilter(start: start, end: end),
      );
      final series = await ReportsRepository.getSalesSeries(
        startMs: start.millisecondsSinceEpoch,
        endMs: end.millisecondsSinceEpoch,
      );

      expect(kpis.totalSales, closeTo(0, 0.001));
      expect(kpis.totalCost, closeTo(0, 0.001));
      expect(kpis.totalProfit, closeTo(0, 0.001));
      expect(report.sales, hasLength(1));
      expect(report.totalSales, closeTo(0, 0.001));
      expect(report.totalCost, closeTo(0, 0.001));
      expect(series.single.value, closeTo(0, 0.001));
    },
  );
}

Map<String, Object?> _saleItem({required int productId, required double qty}) {
  return {
    'product_id': productId,
    'product_code_snapshot': 'P-REP',
    'product_name_snapshot': 'Producto Reporte',
    'qty': qty,
    'unit_price': 10.0,
    'purchase_price_snapshot': 5.0,
    'discount_line': 0.0,
    'total_line': qty * 10.0,
  };
}

Future<int> _insertProduct({required double stock}) async {
  final db = await AppDb.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  return db.insert(DbTables.products, {
    'code': 'P-REP',
    'name': 'Producto Reporte',
    'purchase_price': 5.0,
    'sale_price': 10.0,
    'stock': stock,
    'reserved_stock': 0.0,
    'stock_min': 0.0,
    'is_active': 1,
    'sync_status': 'synced',
    'local_updated_at_ms': now,
    'version': 0,
    'needs_sync': 0,
    'created_at_ms': now,
    'updated_at_ms': now,
  });
}

Future<int> _firstSaleItemId(int saleId) async {
  final db = await AppDb.database;
  final rows = await db.query(
    DbTables.saleItems,
    columns: ['id'],
    where: 'sale_id = ?',
    whereArgs: [saleId],
    limit: 1,
  );
  return rows.first['id'] as int;
}
