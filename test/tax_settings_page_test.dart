import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/features/settings/data/business_settings_model.dart';
import 'package:fullpos/features/settings/data/business_settings_repository.dart';
import 'package:fullpos/features/settings/ui/business_sections_settings_page.dart';
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
    docsDir = await Directory.systemTemp.createTemp('fullpos_tax_settings_');
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

  test('repository persists global ITBIS toggle', () async {
    final repository = BusinessSettingsRepository();

    await repository.saveSettings(
      BusinessSettings(
        businessName: 'FULLPOS',
        defaultTaxRate: 18,
        itbisEnabled: false,
      ),
    );

    final loaded = await repository.loadSettings();
    expect(loaded.itbisEnabled, isFalse);
    expect(loaded.defaultTaxRate, 18);
  });

  testWidgets('tax settings page saves activar ITBIS switch', (tester) async {
    final repository = BusinessSettingsRepository();
    await repository.saveSettings(
      BusinessSettings(
        businessName: 'FULLPOS',
        defaultTaxRate: 18,
        itbisEnabled: true,
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TaxSettingsPage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Activar ITBIS'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final loaded = await repository.loadSettings();
    expect(loaded.itbisEnabled, isFalse);
  });
}
