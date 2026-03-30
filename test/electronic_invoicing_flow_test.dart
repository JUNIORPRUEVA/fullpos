import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_company_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/factura_electronica_repository.dart';
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

  test('invoice sale stores simulated e-CF document', () async {
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
      company.copyWith(
        environment: 'pruebas',
        automaticEmission: 1,
      ),
    );

    final saleId = await SalesRepository.createSale(
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
      electronicDocumentType: 'eCF',
    );

    final factura = await FacturaElectronicaRepository.getBySaleId(saleId);

    expect(factura, isNotNull);
    expect(factura!.saleId, saleId);
    expect(factura.tipoDocumento, 'eCF');
    expect(factura.estadoDgii, FacturaElectronicaModel.statusAccepted);
    expect(factura.ecf, isNotEmpty);
    expect(factura.xmlPayload, contains('<eCF>'));
    expect(factura.xmlFirmado, contains('<FirmaDigital'));
  });
}