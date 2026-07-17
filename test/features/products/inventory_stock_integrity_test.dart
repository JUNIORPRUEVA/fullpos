import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/features/products/data/products_repository.dart';
import 'package:fullpos/features/products/data/stock_repository.dart';
import 'package:fullpos/features/products/models/product_model.dart';
import 'package:fullpos/features/products/models/stock_movement_model.dart';
import 'package:fullpos/features/purchases/data/purchases_repository.dart';
import 'package:fullpos/features/sales/data/layaway_repository.dart';
import 'package:fullpos/features/sales/data/returns_repository.dart';
import 'package:fullpos/features/sales/data/sales_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

int _productSequence = 0;

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
    tempDir = await Directory.systemTemp.createTemp('fullpos_inventory_test_');
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

  test('venta descuenta stock y cancelacion restaura una sola vez', () async {
    final productId = await _insertProduct(stock: 10);

    final saleId = await SalesRepository.saveSaleWithItems(
      localCode: 'V-INV-001',
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

    expect(await _stock(productId), 8);
    expect(await _movementCount(productId, type: 'out'), 1);
    expect(await _movementQuantity(productId, type: 'out'), 2);
    expect(await _needsSync(productId), isTrue);

    expect(await SalesRepository.cancelSale(saleId), isTrue);
    expect(await _stock(productId), 10);
    expect(await _movementCount(productId, type: 'in'), 1);

    expect(await SalesRepository.cancelSale(saleId), isFalse);
    expect(await _stock(productId), 10);
  });

  test(
    'cancelar apartado libera reservado sin aumentar stock fisico',
    () async {
      final productId = await _insertProduct(stock: 10);

      final saleId = await SalesRepository.saveSaleWithItems(
        localCode: 'A-INV-001',
        kind: 'invoice',
        status: 'LAYAWAY',
        itbisEnabled: 0,
        itbisRate: 0,
        discountTotal: 0,
        subtotal: 20,
        itbisAmount: 0,
        total: 20,
        paymentMethod: 'layaway',
        paymentCashAmount: 0,
        paymentCardAmount: 0,
        paymentTransferAmount: 0,
        paidAmount: 0,
        changeAmount: 0,
        creditInterestRate: 0,
        electronicInvoiceEnabled: 0,
        items: [_saleItem(productId: productId, qty: 2)],
        stockUpdateMode: StockUpdateMode.reserve,
      );

      expect(await _stock(productId), 10);
      expect(await _reservedStock(productId), 2);

      expect(await SalesRepository.cancelSale(saleId), isTrue);
      expect(await _stock(productId), 10);
      expect(await _reservedStock(productId), 0);
      expect(await _movementCount(productId), 0);
    },
  );

  test(
    'liquidar apartado descuenta stock reservado exactamente una vez',
    () async {
      final productId = await _insertProduct(stock: 10);
      final saleId = await SalesRepository.saveSaleWithItems(
        localCode: 'A-INV-002',
        kind: 'invoice',
        status: 'LAYAWAY',
        itbisEnabled: 0,
        itbisRate: 0,
        discountTotal: 0,
        subtotal: 20,
        itbisAmount: 0,
        total: 20,
        paymentMethod: 'layaway',
        paymentCashAmount: 0,
        paymentCardAmount: 0,
        paymentTransferAmount: 0,
        paidAmount: 0,
        changeAmount: 0,
        creditInterestRate: 0,
        electronicInvoiceEnabled: 0,
        items: [_saleItem(productId: productId, qty: 2)],
        stockUpdateMode: StockUpdateMode.reserve,
      );
      await _insertOpenCashSession();

      final result = await LayawayRepository.registerLayawayPayment(
        saleId: saleId,
        amount: 20,
        method: 'cash',
        sessionId: 1,
      );

      expect(result.status, 'PAGADO');
      expect(await _stock(productId), 8);
      expect(await _reservedStock(productId), 0);
      expect(await _movementCount(productId, type: 'out'), 1);
      expect(await _movementQuantity(productId, type: 'out'), 2);
    },
  );

  test('venta bloquea stock insuficiente y no deja venta parcial', () async {
    final productId = await _insertProduct(stock: 1);

    await expectLater(
      SalesRepository.saveSaleWithItems(
        localCode: 'V-INV-NOSTOCK',
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
      ),
      throwsA(predicate((e) => e.toString().contains('stock_negative'))),
    );

    expect(await _stock(productId), 1);
    expect(await _movementCount(productId), 0);
    expect(await _saleCount(), 0);
  });

  test(
    'venta sin stock explicita permite negativo y registra salida positiva',
    () async {
      final productId = await _insertProduct(stock: 1);

      await SalesRepository.saveSaleWithItems(
        localCode: 'V-INV-NEG',
        kind: 'invoice',
        allowNegativeStock: true,
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

      expect(await _stock(productId), -1);
      expect(await _movementQuantity(productId, type: 'out'), 2);
    },
  );

  test(
    'modo sin inventario guarda venta sin tocar stock ni movimientos',
    () async {
      final productId = await _insertProduct(stock: 4);

      await SalesRepository.saveSaleWithItems(
        localCode: 'V-INV-NONE',
        kind: 'quote',
        itbisEnabled: 0,
        itbisRate: 0,
        discountTotal: 0,
        subtotal: 20,
        itbisAmount: 0,
        total: 20,
        paymentMethod: null,
        paymentCashAmount: 0,
        paymentCardAmount: 0,
        paymentTransferAmount: 0,
        paidAmount: 0,
        changeAmount: 0,
        creditInterestRate: 0,
        electronicInvoiceEnabled: 0,
        items: [_saleItem(productId: productId, qty: 2)],
        stockUpdateMode: StockUpdateMode.none,
      );

      expect(await _stock(productId), 4);
      expect(await _movementCount(productId), 0);
    },
  );

  test('venta con codigo resuelve producto y descuenta stock', () async {
    final productId = await _insertProduct(stock: 10);

    await SalesRepository.saveSaleWithItems(
      localCode: 'V-INV-CODE',
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
      items: [
        {
          ..._saleItem(productId: productId, qty: 2),
          'product_id': null,
          'product_code_snapshot': ' p-inv-${_productSequence - 1} ',
        },
      ],
    );

    expect(await _stock(productId), 8);
    expect(await _movementCount(productId, type: 'out'), 1);
  });

  test(
    'venta con codigo no resuelto no se guarda sin descontar inventario',
    () async {
      final productId = await _insertProduct(stock: 10);

      await expectLater(
        SalesRepository.saveSaleWithItems(
          localCode: 'V-INV-MISSING-CODE',
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
          items: [
            {
              ..._saleItem(productId: productId, qty: 2),
              'product_id': null,
              'product_code_snapshot': 'NO-EXISTE',
            },
          ],
        ),
        throwsA(predicate((e) => e.toString().contains('product_not_found'))),
      );

      expect(await _stock(productId), 10);
      expect(await _movementCount(productId), 0);
      expect(await _saleCount(), 0);
    },
  );

  test('item manual no exige producto ni toca inventario', () async {
    final productId = await _insertProduct(stock: 10);

    await SalesRepository.saveSaleWithItems(
      localCode: 'V-INV-MANUAL',
      kind: 'invoice',
      itbisEnabled: 0,
      itbisRate: 0,
      discountTotal: 0,
      subtotal: 15,
      itbisAmount: 0,
      total: 15,
      paymentMethod: 'cash',
      paymentCashAmount: 15,
      paymentCardAmount: 0,
      paymentTransferAmount: 0,
      paidAmount: 15,
      changeAmount: 0,
      creditInterestRate: 0,
      electronicInvoiceEnabled: 0,
      items: [
        {
          'product_id': null,
          'product_code_snapshot': 'MANUAL',
          'product_name_snapshot': 'Item Manual',
          'qty': 1,
          'unit_price': 15.0,
          'purchase_price_snapshot': 0.0,
          'discount_line': 0.0,
          'total_line': 15.0,
        },
      ],
    );

    expect(await _stock(productId), 10);
    expect(await _movementCount(productId), 0);
    expect(await _saleCount(), 1);
  });

  test(
    'producto eliminado se puede crear nuevamente por codigo normalizado',
    () async {
      final repo = ProductsRepository();
      final now = DateTime.now().millisecondsSinceEpoch;
      final firstId = await repo.create(
        ProductModel(
          code: ' ABC-001 ',
          name: 'Producto Original',
          purchasePrice: 5,
          salePrice: 10,
          stock: 3,
          stockMin: 1,
          placeholderType: 'color',
          placeholderColorHex: '#1A56DB',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      await repo.softDelete(firstId);

      final recreatedId = await repo.create(
        ProductModel(
          code: 'abc-001',
          name: 'Producto Recreado',
          purchasePrice: 6,
          salePrice: 12,
          stock: 7,
          stockMin: 2,
          placeholderType: 'color',
          placeholderColorHex: '#0F766E',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      final recreated = await repo.getByCode(' ABC-001 ');

      expect(recreatedId, firstId);
      expect(recreated, isNotNull);
      expect(recreated!.deletedAtMs, isNull);
      expect(recreated.isActive, isTrue);
      expect(recreated.name, 'Producto Recreado');
      expect(recreated.stock, 7);
      expect(await repo.existsByCode('ABC-001'), isTrue);
    },
  );

  test(
    'resumen y filtros interpretan salidas positivas, negativas y legacy',
    () async {
      final productId = await _insertProduct(stock: 10);
      final db = await AppDb.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert(DbTables.stockMovements, {
        'product_id': productId,
        'type': 'out',
        'quantity': 2.0,
        'created_at_ms': now,
      });
      await db.insert(DbTables.stockMovements, {
        'product_id': productId,
        'type': 'out',
        'quantity': -3.0,
        'created_at_ms': now,
      });
      await db.insert(DbTables.stockMovements, {
        'product_id': productId,
        'type': 'SALE',
        'quantity': -4.0,
        'created_at_ms': now,
      });
      await db.insert(DbTables.stockMovements, {
        'product_id': productId,
        'type': 'CANCELLATION',
        'quantity': 1.0,
        'created_at_ms': now,
      });

      final repo = StockRepository();
      final summary = await repo.summarize(productId: productId);
      final outputs = await repo.getDetailedHistory(
        productId: productId,
        type: StockMovementType.output,
      );

      expect(summary.totalInputs, 1);
      expect(summary.totalOutputs, 9);
      expect(summary.netChange, -8);
      expect(outputs, hasLength(3));
      expect(
        await repo.count(productId: productId, type: StockMovementType.output),
        3,
      );
    },
  );

  test(
    'devolucion restaura solo la cantidad devuelta y bloquea exceso',
    () async {
      final productId = await _insertProduct(stock: 10);
      final saleId = await SalesRepository.saveSaleWithItems(
        localCode: 'V-INV-002',
        kind: 'invoice',
        itbisEnabled: 0,
        itbisRate: 0,
        discountTotal: 0,
        subtotal: 30,
        itbisAmount: 0,
        total: 30,
        paymentMethod: 'cash',
        paymentCashAmount: 30,
        paymentCardAmount: 0,
        paymentTransferAmount: 0,
        paidAmount: 30,
        changeAmount: 0,
        creditInterestRate: 0,
        electronicInvoiceEnabled: 0,
        items: [_saleItem(productId: productId, qty: 3)],
      );
      final saleItemId = await _firstSaleItemId(saleId);

      await ReturnsRepository.createReturn(
        originalSaleId: saleId,
        note: 'prueba inventario',
        returnItems: [
          {'sale_item_id': saleItemId, 'qty': 1},
        ],
      );

      expect(await _stock(productId), 8);
      expect(await _movementCount(productId, type: 'in'), 1);

      await expectLater(
        ReturnsRepository.createReturn(
          originalSaleId: saleId,
          note: 'exceso',
          returnItems: [
            {'sale_item_id': saleItemId, 'qty': 3},
          ],
        ),
        throwsA(predicate((e) => e.toString().contains('más cantidad'))),
      );
      expect(await _stock(productId), 8);
    },
  );

  test(
    'recepcion de compra suma inventario y no permite recibir de mas',
    () async {
      final productId = await _insertProduct(stock: 5);
      final db = await AppDb.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final supplierId = await db.insert(DbTables.suppliers, {
        'name': 'Suplidor prueba',
        'created_at_ms': now,
        'updated_at_ms': now,
      });
      final repo = PurchasesRepository();
      final orderId = await repo.createOrder(
        supplierId: supplierId,
        taxRatePercent: 0,
        items: [
          repo.itemInput(
            productId: productId,
            productCodeSnapshot: 'P-INV',
            productNameSnapshot: 'Producto Inventario',
            qty: 4,
            unitCost: 5,
          ),
        ],
      );
      final itemId = await _firstPurchaseItemId(orderId);

      await repo.receiveItem(orderId: orderId, itemId: itemId, qtyToReceive: 2);
      expect(await _stock(productId), 7);
      expect(await _movementCount(productId, type: 'in'), 1);
      expect(await _needsSync(productId), isTrue);

      await expectLater(
        repo.receiveItem(orderId: orderId, itemId: itemId, qtyToReceive: 3),
        throwsA(predicate((e) => e.toString().contains('más de lo pendiente'))),
      );
      expect(await _stock(productId), 7);
    },
  );
}

Map<String, Object?> _saleItem({required int productId, required double qty}) {
  return {
    'product_id': productId,
    'product_code_snapshot': 'P-INV',
    'product_name_snapshot': 'Producto Inventario',
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
  final sequence = _productSequence++;
  return db.insert(DbTables.products, {
    'code': 'P-INV-$sequence',
    'name': 'Producto Inventario',
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

Future<void> _insertOpenCashSession() async {
  final db = await AppDb.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert(DbTables.cashSessions, {
    'id': 1,
    'opened_by_user_id': 1,
    'user_name': 'Admin',
    'opened_at_ms': now,
    'initial_amount': 0.0,
    'requires_closure': 0,
    'status': 'OPEN',
  });
}

Future<double> _stock(int productId) async {
  final db = await AppDb.database;
  final rows = await db.query(
    DbTables.products,
    columns: ['stock'],
    where: 'id = ?',
    whereArgs: [productId],
    limit: 1,
  );
  return (rows.first['stock'] as num).toDouble();
}

Future<double> _reservedStock(int productId) async {
  final db = await AppDb.database;
  final rows = await db.query(
    DbTables.products,
    columns: ['reserved_stock'],
    where: 'id = ?',
    whereArgs: [productId],
    limit: 1,
  );
  return (rows.first['reserved_stock'] as num).toDouble();
}

Future<bool> _needsSync(int productId) async {
  final db = await AppDb.database;
  final rows = await db.query(
    DbTables.products,
    columns: ['needs_sync', 'sync_status'],
    where: 'id = ?',
    whereArgs: [productId],
    limit: 1,
  );
  return rows.first['needs_sync'] == 1 &&
      rows.first['sync_status'] == 'pending';
}

Future<int> _movementCount(int productId, {String? type}) async {
  final db = await AppDb.database;
  final where = type == null ? 'product_id = ?' : 'product_id = ? AND type = ?';
  final args = type == null ? [productId] : [productId, type];
  return Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM ${DbTables.stockMovements} WHERE $where',
          args,
        ),
      ) ??
      0;
}

Future<double> _movementQuantity(int productId, {required String type}) async {
  final db = await AppDb.database;
  final rows = await db.rawQuery(
    '''
    SELECT quantity
    FROM ${DbTables.stockMovements}
    WHERE product_id = ? AND type = ?
    ORDER BY id DESC
    LIMIT 1
    ''',
    [productId, type],
  );
  return (rows.first['quantity'] as num).toDouble();
}

Future<int> _saleCount() async {
  final db = await AppDb.database;
  return Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ${DbTables.sales}'),
      ) ??
      0;
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

Future<int> _firstPurchaseItemId(int orderId) async {
  final db = await AppDb.database;
  final rows = await db.query(
    DbTables.purchaseOrderItems,
    columns: ['id'],
    where: 'order_id = ?',
    whereArgs: [orderId],
    limit: 1,
  );
  return rows.first['id'] as int;
}
