import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/db/tables.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_sequence_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_company_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/factura_electronica_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/electronic_sequence_model.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/factura_electronica_model.dart';
import 'package:fullpos/features/sales/data/sales_repository.dart';
import 'package:fullpos/features/settings/data/business_settings_model.dart';
import 'package:fullpos/features/settings/data/business_settings_repository.dart';
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
    docsDir = await Directory.systemTemp.createTemp('fullpos_ecf_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> saveSequence({
    required String documentTypeCode,
    required String prefix,
    required int endNumber,
  }) async {
    await ElectronicSequenceRepository().saveLocal(
      ElectronicSequenceModel(
        companyId: 1,
        branchId: 0,
        documentTypeCode: documentTypeCode,
        prefix: prefix,
        startNumber: 1,
        currentNumber: 0,
        endNumber: endNumber,
        status: 'ACTIVE',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  test('invoice sale is rolled back when real FE backend is unavailable', () async {
    await AppDb.resetForTests();

    await BusinessSettingsRepository().saveSettings(
      BusinessSettings(
        businessName: 'FULLPOS SRL',
        rnc: '101010101',
        address: 'Santo Domingo',
      ),
    );

    final company = await ElectronicCompanyRepository.getOrCreate();
    await ElectronicCompanyRepository.save(
      company.copyWith(environment: 'pruebas', automaticEmission: 1),
    );

    await saveSequence(documentTypeCode: '31', prefix: 'E31', endNumber: 31);

    await expectLater(
      SalesRepository.createSale(
        localCode: 'V-ECF-TEST-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'ECF-001',
            'product_name_snapshot': 'Producto e-CF',
            'qty': 1.0,
            'unit_price': 250.0,
            'purchase_price_snapshot': 120.0,
            'discount_line': 0.0,
            'total_line': 250.0,
          },
        ],
        itbisEnabled: false,
        subtotalOverride: 250.0,
        itbisAmountOverride: 0.0,
        totalOverride: 250.0,
        paymentMethod: 'cash',
        paymentCashAmount: 250.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        paidAmount: 250.0,
        changeAmount: 0.0,
        electronicInvoiceEnabled: true,
        electronicDocumentType: '31',
        customerName: 'CLIENTE FISCAL 1',
        customerRnc: '131000001',
      ),
      throwsException,
    );

    final salesRows = await (await AppDb.database).query(
      DbTables.sales,
      columns: ['id', 'deleted_at_ms', 'status'],
      where: 'local_code = ?',
      whereArgs: ['V-ECF-TEST-001'],
    );

    expect(salesRows, isNotEmpty);
    final saleId = salesRows.first['id'] as int;

    final factura = await FacturaElectronicaRepository.getBySaleId(saleId);
    expect(factura, isNull);
    expect(salesRows.first['deleted_at_ms'], isNotNull);
    expect(salesRows.first['status'], 'cancelled_fe');
  });

  test('saveLocal ignores remote id collisions and preserves business upsert key', () async {
    await AppDb.resetForTests();

    final repository = ElectronicSequenceRepository();
    final first = await repository.saveLocal(
      ElectronicSequenceModel(
        companyId: 1,
        branchId: 0,
        documentTypeCode: '32',
        prefix: 'E32',
        startNumber: 1,
        currentNumber: 0,
        endNumber: 100,
        status: 'ACTIVE',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(first.id, isNotNull);

    final saved = await repository.saveLocal(
      ElectronicSequenceModel(
        id: first.id,
        companyId: 1,
        branchId: 0,
        documentTypeCode: '31',
        prefix: 'E31',
        startNumber: 1,
        currentNumber: 0,
        endNumber: 200,
        status: 'ACTIVE',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(saved.id, isNotNull);
    expect(saved.id, isNot(first.id));

    final rows = await (await AppDb.database).query(
      'electronic_sequences',
      orderBy: 'document_type_code ASC',
    );

    expect(rows, hasLength(2));
    expect(rows.map((row) => row['document_type_code']), ['31', '32']);
  });

  test(
    'invoice sale stores customer RNC snapshot for fiscal printing',
    () async {
      await AppDb.resetForTests();

      final saleId = await SalesRepository.createSale(
        localCode: 'V-ECF-TEST-CLIENT-001',
        kind: 'invoice',
        items: [
          {
            'product_code_snapshot': 'ECF-002',
            'product_name_snapshot': 'Producto fiscal',
            'qty': 1.0,
            'unit_price': 300.0,
            'purchase_price_snapshot': 150.0,
            'discount_line': 0.0,
            'total_line': 300.0,
          },
        ],
        itbisEnabled: false,
        subtotalOverride: 300.0,
        itbisAmountOverride: 0.0,
        totalOverride: 300.0,
        paymentMethod: 'cash',
        paymentCashAmount: 300.0,
        paymentCardAmount: 0.0,
        paymentTransferAmount: 0.0,
        paidAmount: 300.0,
        changeAmount: 0.0,
        electronicInvoiceEnabled: false,
        electronicDocumentType: '31',
        customerName: 'EMPRESA CLIENTE SRL',
        customerPhone: '8095550001',
        customerRnc: '131246796',
      );

      final sale = await SalesRepository.getSaleById(saleId);

      expect(sale, isNotNull);
      expect(sale!.customerNameSnapshot, 'EMPRESA CLIENTE SRL');
      expect(sale.customerRncSnapshot, '131246796');
    },
  );
}
