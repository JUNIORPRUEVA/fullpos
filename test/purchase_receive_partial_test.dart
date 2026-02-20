import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/features/products/data/products_repository.dart';
import 'package:fullpos/features/products/data/suppliers_repository.dart';
import 'package:fullpos/features/products/models/product_model.dart';
import 'package:fullpos/features/products/models/supplier_model.dart';
import 'package:fullpos/features/purchases/data/purchases_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this._docsDir);

  final Directory _docsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => _docsDir.path;

  @override
  Future<String?> getLibraryPath() async => _docsDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUpAll(() async {
    DbInit.ensureInitialized();
    docsDir = await Directory.systemTemp.createTemp('fullpos_purchase_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  test('Compras: recibir por producto y anular revierte stock', () async {
    await AppDb.resetForTests();

    final suppliersRepo = SuppliersRepository();
    final productsRepo = ProductsRepository();
    final purchasesRepo = PurchasesRepository();

    final now = DateTime.now().millisecondsSinceEpoch;

    final supplierId = await suppliersRepo.create(
      SupplierModel(
        name: 'Proveedor Test',
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );

    final productAId = await productsRepo.create(
      ProductModel(
        code: 'TEST-A',
        name: 'Producto A',
        placeholderType: 'color',
        purchasePrice: 10,
        salePrice: 20,
        stock: 0,
        stockMin: 0,
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );

    final productBId = await productsRepo.create(
      ProductModel(
        code: 'TEST-B',
        name: 'Producto B',
        placeholderType: 'color',
        purchasePrice: 15,
        salePrice: 30,
        stock: 0,
        stockMin: 0,
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );

    final orderId = await purchasesRepo.createOrder(
      supplierId: supplierId,
      taxRatePercent: 0,
      notes: 'Orden test',
      isAuto: false,
      items: [
        purchasesRepo.itemInput(
          productId: productAId,
          productCodeSnapshot: 'TEST-A',
          productNameSnapshot: 'Producto A',
          qty: 5,
          unitCost: 10,
        ),
        purchasesRepo.itemInput(
          productId: productBId,
          productCodeSnapshot: 'TEST-B',
          productNameSnapshot: 'Producto B',
          qty: 2,
          unitCost: 15,
        ),
      ],
    );

    var detail = await purchasesRepo.getOrderById(orderId);
    expect(detail, isNotNull);
    expect(detail!.order.status.trim().toUpperCase(), 'PENDIENTE');

    final itemA = detail.items.firstWhere((e) => e.item.productId == productAId);
    final itemB = detail.items.firstWhere((e) => e.item.productId == productBId);

    await purchasesRepo.receiveItem(
      orderId: orderId,
      itemId: itemA.item.id!,
      qtyToReceive: 5,
    );

    detail = await purchasesRepo.getOrderById(orderId);
    expect(detail, isNotNull);
    expect(detail!.order.status.trim().toUpperCase(), 'PARCIAL');

    final prodA = await productsRepo.getById(productAId);
    expect(prodA, isNotNull);
    expect(prodA!.stock, closeTo(5, 1e-9));

    final itemAAfter = detail.items.firstWhere((e) => e.item.productId == productAId);
    expect(itemAAfter.item.receivedQty, closeTo(5, 1e-9));

    await purchasesRepo.receiveItem(
      orderId: orderId,
      itemId: itemB.item.id!,
      qtyToReceive: 2,
    );

    detail = await purchasesRepo.getOrderById(orderId);
    expect(detail, isNotNull);
    expect(detail!.order.status.trim().toUpperCase(), 'RECIBIDA');
    expect(detail.order.receivedAtMs, isNotNull);

    final prodB = await productsRepo.getById(productBId);
    expect(prodB, isNotNull);
    expect(prodB!.stock, closeTo(2, 1e-9));

    await purchasesRepo.cancelReceipt(orderId);

    detail = await purchasesRepo.getOrderById(orderId);
    expect(detail, isNotNull);
    expect(detail!.order.status.trim().toUpperCase(), 'PENDIENTE');
    expect(detail.order.receivedAtMs, isNull);

    final prodA2 = await productsRepo.getById(productAId);
    final prodB2 = await productsRepo.getById(productBId);
    expect(prodA2!.stock, closeTo(0, 1e-9));
    expect(prodB2!.stock, closeTo(0, 1e-9));

    final aReset = detail.items.firstWhere((e) => e.item.productId == productAId);
    final bReset = detail.items.firstWhere((e) => e.item.productId == productBId);
    expect(aReset.item.receivedQty, closeTo(0, 1e-9));
    expect(bReset.item.receivedQty, closeTo(0, 1e-9));

    await purchasesRepo.deleteOrder(orderId);

    final deleted = await purchasesRepo.getOrderById(orderId);
    expect(deleted, isNull);
  });
}
