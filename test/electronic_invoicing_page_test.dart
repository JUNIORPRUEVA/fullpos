import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_company_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/electronic_company_model.dart';
import 'package:fullpos/features/settings/data/business_settings_model.dart';
import 'package:fullpos/features/settings/data/business_settings_repository.dart';
import 'package:fullpos/features/tools/ui/electronic_invoicing_page.dart';
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
    docsDir = await Directory.systemTemp.createTemp('fullpos_ecf_page_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await AppDb.resetForTests();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ElectronicInvoicingPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows company data as read-only from business settings', (
    tester,
  ) async {
    await BusinessSettingsRepository().saveSettings(
      BusinessSettings(
        businessName: 'FULLTECH SRL',
        rnc: '123456789',
        address: 'Higuey',
        city: 'La Altagracia',
      ),
    );

    final company = await ElectronicCompanyRepository.getOrCreate();
    await ElectronicCompanyRepository.save(
      company.copyWith(
        environment: 'pruebas',
        apiToken: 'token-demo',
        certificateName: 'cert-demo',
        automaticEmission: 1,
      ),
    );

    await pumpPage(tester);

    expect(find.text('Datos de la empresa'), findsOneWidget);
    expect(find.text('FULLTECH SRL'), findsOneWidget);
    expect(find.text('123456789'), findsOneWidget);
    expect(find.text('Higuey, La Altagracia'), findsOneWidget);
    expect(
      find.text('Complete la información de empresa en configuración'),
      findsNothing,
    );
    expect(find.text('Razon social'), findsNothing);
    expect(find.text('Nombre comercial'), findsNothing);
    expect(find.text('Direccion de emision'), findsNothing);
    expect(find.text('Telefono'), findsNothing);
  });

  testWidgets('shows configuration CTA when company data is incomplete', (
    tester,
  ) async {
    final company = await ElectronicCompanyRepository.getOrCreate();
    await ElectronicCompanyRepository.save(
      company.copyWith(environment: 'pruebas', automaticEmission: 1),
    );

    await pumpPage(tester);

    expect(
      find.text('Complete la información de empresa en configuración'),
      findsOneWidget,
    );
    expect(find.text('Ir a configuración'), findsOneWidget);
  });

  test('repository clears duplicated company identity fields on save', () async {
    await AppDb.resetForTests();

    final saved = await ElectronicCompanyRepository.save(
      ElectronicCompanyModel.defaults().copyWith(
        businessName: 'Empresa duplicada',
        tradeName: 'Trade duplicado',
        rnc: '999999999',
        emissionAddress: 'Direccion duplicada',
        phone: '8090000000',
        email: 'duplicado@correo.com',
        environment: 'produccion',
        apiToken: 'token-seguro',
        certificateName: 'certificado',
        automaticEmission: 0,
      ),
    );

    expect(saved.businessName, isEmpty);
    expect(saved.rnc, isEmpty);

    final db = await AppDb.database;
    final rows = await db.query('electronic_company', limit: 1);
    expect(rows, isNotEmpty);

    final row = rows.first;
    expect(row['business_name'], '');
    expect(row['trade_name'], '');
    expect(row['rnc'], '');
    expect(row['emission_address'], '');
    expect(row['phone'], '');
    expect(row['email'], '');
    expect(row['environment'], 'produccion');
    expect(row['api_token'], 'token-seguro');
    expect(row['certificate_name'], 'certificado');
    expect(row['automatic_emission'], 0);
  });
}