import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/features/fiscal_receipts/data/fiscal_receipt_models.dart';
import 'package:fullpos/features/fiscal_receipts/data/fiscal_receipt_repository.dart';

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
    tempDir = await Directory.systemTemp.createTemp('fullpos_ncf_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await AppDb.resetForTests();
  });

  tearDown(() async {
    await AppDb.resetForTests();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('nuevo comprobante debe iniciar en el desde del rango', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    expect(
      () => FiscalReceiptRepository.saveType(
        FiscalReceiptTypeModel(
          name: 'Credito fiscal',
          code: '01',
          prefix: 'B01',
          startNumber: 12,
          nextNumber: 15,
          endNumber: 15,
          sequenceDigits: 8,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ),
      throwsArgumentError,
    );

    final typeId = await FiscalReceiptRepository.saveType(
      FiscalReceiptTypeModel(
        name: 'Credito fiscal',
        code: '01',
        prefix: 'B01',
        startNumber: 12,
        nextNumber: 12,
        endNumber: 15,
        sequenceDigits: 8,
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );

    final firstSaleId = await _insertSale('V-TEST-001');
    final secondSaleId = await _insertSale('V-TEST-002');
    final db = await AppDb.database;

    final first = await db.transaction(
      (txn) => FiscalReceiptRepository.reserveNextReceiptForSale(
        txn: txn,
        receiptTypeId: typeId,
        saleId: firstSaleId,
      ),
    );
    final second = await db.transaction(
      (txn) => FiscalReceiptRepository.reserveNextReceiptForSale(
        txn: txn,
        receiptTypeId: typeId,
        saleId: secondSaleId,
      ),
    );

    expect(first.sequenceNumber, 12);
    expect(first.receiptNumber, 'B0100000012');
    expect(second.sequenceNumber, 13);
    expect(second.receiptNumber, 'B0100000013');

    final saved = await FiscalReceiptRepository.getTypeById(typeId);
    expect(saved?.nextNumber, 14);
  });
}

Future<int> _insertSale(String localCode) async {
  final db = await AppDb.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  return db.insert(DbTables.sales, {
    'local_code': localCode,
    'kind': 'invoice',
    'status': 'completed',
    'itbis_enabled': 1,
    'itbis_rate': 0.18,
    'discount_total': 0.0,
    'subtotal': 100.0,
    'itbis_amount': 18.0,
    'total': 118.0,
    'payment_cash_amount': 118.0,
    'payment_card_amount': 0.0,
    'payment_transfer_amount': 0.0,
    'paid_amount': 118.0,
    'change_amount': 0.0,
    'credit_interest_rate': 0.0,
    'electronic_invoice_enabled': 0,
    'fiscal_enabled': 0,
    'created_at_ms': now,
    'updated_at_ms': now,
  });
}
