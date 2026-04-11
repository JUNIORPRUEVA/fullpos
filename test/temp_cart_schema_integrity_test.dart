import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/features/sales/data/sale_item_model.dart';
import 'package:fullpos/features/sales/data/temp_cart_repository.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUpAll(() async {
    DbInit.ensureInitialized();
    docsDir = await Directory.systemTemp.createTemp('fullpos_temp_cart_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'repara temp_carts legado sin electronic_invoice_enabled y saveCart funciona',
    () async {
      await AppDb.resetForTests();

      final legacyPath = p.join(docsDir.path, AppDb.dbFileName);
      final legacyDb = await openDatabase(
        legacyPath,
        version: AppDb.schemaVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE ${DbTables.tempCarts} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              user_id INTEGER,
              client_id INTEGER,
              discount REAL NOT NULL DEFAULT 0,
              itbis_enabled INTEGER NOT NULL DEFAULT 1,
              itbis_rate REAL NOT NULL DEFAULT 0.18,
              fiscal_enabled INTEGER NOT NULL DEFAULT 0,
              discount_total_type TEXT,
              discount_total_value REAL,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL
            )
          ''');
        },
      );
      await legacyDb.close();

      final repo = TempCartRepository();
      final cartId = await repo.saveCart(
        name: 'Ticket 1',
        userId: 1,
        clientId: null,
        discount: 0,
        itbisEnabled: false,
        itbisRate: 0.18,
        electronicInvoiceEnabled: false,
        discountTotalType: null,
        discountTotalValue: null,
        items: const <SaleItemModel>[],
      );

      expect(cartId, greaterThan(0));

      final db = await AppDb.database;
      final columns = await db.rawQuery(
        'PRAGMA table_info(${DbTables.tempCarts})',
      );
      final columnNames = columns
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();

      expect(columnNames, contains('electronic_invoice_enabled'));
    },
  );
}
