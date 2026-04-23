
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_company_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_sequence_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/electronic_invoicing_config_model.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/electronic_company_model.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/electronic_sequence_model.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/factura_electronica_model.dart';
import 'package:fullpos/features/settings/data/business_settings_model.dart';
import 'package:fullpos/features/settings/data/business_settings_repository.dart';
import 'package:fullpos/features/tools/ui/electronic_invoicing_page.dart';
import 'package:fullpos/core/services/empresa_service.dart';
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

  ElectronicInvoicingResolvedConfig resolvedConfigForTest({
    required ElectronicCompanyModel company,
    required List<ElectronicSequenceModel> sequences,
    required List<String> missing,
    List<String> messages = const <String>[],
  }) {
    return ElectronicInvoicingResolvedConfig.localFallback(
      company: company,
      sequences: sequences,
      missing: missing,
      messages: messages,
    );
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required BusinessSettings businessSettings,
    required ElectronicInvoicingResolvedConfig resolvedConfig,
  }) async {
    final empresaConfig = EmpresaConfig.fromBusinessSettings(businessSettings);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ElectronicInvoicingPage(
            loadResolvedConfig: () async => resolvedConfig,
            loadRecentInvoices: () async => const <FacturaElectronicaModel>[],
            loadEmpresaConfig: () async => empresaConfig,
            businessSettingsOverride: businessSettings,
          ),
        ),
      ),
    );
    for (var index = 0; index < 40; index++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Datos de la empresa').evaluate().isNotEmpty) {
        break;
      }
    }
  }

  testWidgets('shows company data as read-only from business settings', (
    tester,
  ) async {
    final businessSettings = BusinessSettings(
      businessName: 'FULLTECH SRL',
      rnc: '123456789',
      address: 'Higuey',
      city: 'La Altagracia',
    );
    final company = ElectronicCompanyModel.defaults().copyWith(
        environment: 'pruebas',
        apiToken: 'token-demo',
        certificateName: 'cert-demo',
        certificateValidFromMs: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        certificateValidToMs: DateTime(2027, 1, 1).millisecondsSinceEpoch,
        certificateStatus: 'active',
        automaticEmission: 1,
    );
    final resolvedConfig = resolvedConfigForTest(
      company: company,
      sequences: [
        ElectronicSequenceModel.defaults('31').copyWith(
        prefix: 'E31',
        startNumber: 1,
        currentNumber: 15,
        endNumber: 200,
        status: 'ACTIVE',
        ),
        ElectronicSequenceModel.defaults('32').copyWith(
        prefix: 'E32',
        startNumber: 1,
        currentNumber: 7,
        endNumber: 200,
        status: 'ACTIVE',
        ),
        ElectronicSequenceModel.defaults('34').copyWith(
          prefix: 'E34',
          startNumber: 1,
          currentNumber: 0,
          endNumber: 50,
          status: 'ACTIVE',
        ),
      ],
      missing: const <String>[],
    );

    await pumpPage(
      tester,
      businessSettings: businessSettings,
      resolvedConfig: resolvedConfig,
    );

    expect(find.text('Empresa cargada'), findsOneWidget);
    expect(find.text('FULLTECH SRL'), findsOneWidget);
    expect(find.text('123456789'), findsOneWidget);
    expect(find.text('Higuey, La Altagracia'), findsOneWidget);
    expect(find.text('Certificado digital y DGII'), findsOneWidget);
    expect(find.text('cert-demo'), findsWidgets);
    expect(find.text('Vigente'), findsWidgets);
    expect(find.text('Facturación Electrónica'), findsOneWidget);
    expect(find.text('LISTO'), findsOneWidget);
    expect(find.text('Configurar automáticamente'), findsOneWidget);
    expect(find.text('Comprobantes fiscales'), findsOneWidget);
    expect(find.text('31 - Crédito Fiscal'), findsOneWidget);
    expect(find.text('32 - Consumo'), findsOneWidget);
    expect(find.text('Completar'), findsNothing);
  });

  testWidgets('shows configuration CTA when company data is incomplete', (
    tester,
  ) async {
    final businessSettings = BusinessSettings.defaultSettings;
    final resolvedConfig = resolvedConfigForTest(
      company: ElectronicCompanyModel.defaults().copyWith(
        environment: 'pruebas',
        automaticEmission: 1,
      ),
      sequences: const <ElectronicSequenceModel>[],
      missing: const <String>['Certificado', 'Secuencia 31', 'Secuencia 32'],
    );

    await pumpPage(
      tester,
      businessSettings: businessSettings,
      resolvedConfig: resolvedConfig,
    );

    expect(find.text('Empresa cargada'), findsOneWidget);
    expect(find.text('Completar'), findsOneWidget);
    expect(find.text('Sin completar'), findsWidgets);
    expect(find.text('No cargado'), findsWidgets);
    expect(find.text('PARCIAL'), findsOneWidget);
  });

  testWidgets('allows showing the .p12 certificate password', (tester) async {
    final businessSettings = BusinessSettings(
      businessName: 'FULLTECH SRL',
      rnc: '123456789',
      address: 'Higuey',
      city: 'La Altagracia',
    );
    final resolvedConfig = resolvedConfigForTest(
      company: ElectronicCompanyModel.defaults().copyWith(environment: 'pruebas'),
      sequences: const <ElectronicSequenceModel>[],
      missing: const <String>['Certificado'],
    );

    await pumpPage(
      tester,
      businessSettings: businessSettings,
      resolvedConfig: resolvedConfig,
    );

    expect(
      find.byKey(const Key('electronic-certificate-password-field')),
      findsNothing,
    );
  });

  testWidgets('shows automatic configuration action and prefills sequences', (
    tester,
  ) async {
    final resolvedConfig = resolvedConfigForTest(
      company: ElectronicCompanyModel.defaults().copyWith(environment: 'pruebas'),
      sequences: const <ElectronicSequenceModel>[],
      missing: const <String>['Certificado'],
    );

    await pumpPage(
      tester,
      businessSettings: BusinessSettings.defaultSettings,
      resolvedConfig: resolvedConfig,
    );

    expect(find.text('Configurar automáticamente'), findsOneWidget);
    expect(find.text('Comprobantes fiscales'), findsOneWidget);
    expect(find.text('31 - Crédito Fiscal'), findsOneWidget);
    expect(find.text('32 - Consumo'), findsOneWidget);
    expect(find.text('34 - Nota de crédito'), findsOneWidget);
    expect(
      find.text(
        'Cada empresa debe configurar su rango real autorizado por DGII. Sin límite autorizado no se puede facturar.',
      ),
      findsOneWidget,
    );
  });

  test(
    'repository clears duplicated company identity fields on save',
    () async {
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
      expect(row['certificate_valid_from_ms'], isNull);
      expect(row['certificate_valid_to_ms'], isNull);
      expect(row['certificate_status'], '');
      expect(row['automatic_emission'], 0);
    },
  );

  testWidgets('shows FE toggles when electronic invoicing is active', (
    tester,
  ) async {
    await BusinessSettingsRepository().saveSettings(
      BusinessSettings(
        businessName: 'FULLTECH SRL',
        electronicInvoicingEnabled: true,
      ),
    );

    final company = await ElectronicCompanyRepository.getOrCreate();
    await ElectronicCompanyRepository.save(
      company.copyWith(environment: 'pruebas', automaticEmission: 1),
    );

    await pumpPage(
      tester,
      businessSettings: await BusinessSettingsRepository().loadSettings(),
      resolvedConfig: resolvedConfigForTest(
        company: company,
        sequences: const <ElectronicSequenceModel>[],
        missing: const <String>['Certificado'],
      ),
    );

    expect(find.text('Facturación Electrónica'), findsOneWidget);
    expect(find.text('Facturación electrónica'), findsOneWidget);
    expect(find.text('Enviar automáticamente a DGII'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
  });
}
