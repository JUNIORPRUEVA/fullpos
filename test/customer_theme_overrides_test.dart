import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/features/settings/data/theme_settings_model.dart';
import 'package:fullpos/features/settings/data/theme_settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    docsDir = await Directory.systemTemp.createTemp('fullpos_docs_theme_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  test('Customer theme overrides are per company_id', () async {
    await AppDb.resetForTests();

    final repo = ThemeSettingsRepository();

    await SessionManager.setCompanyId(1);

    // Baseline is always the shipped default theme.
    final base1 = await repo.loadThemeSettings();
    expect(base1, ThemeSettings.defaultSettings);

    final purplePrimary = ThemeSettings.defaultSettings.copyWith(
      primaryColor: Colors.purple,
    );

    await repo.saveThemeSettings(purplePrimary);

    final loaded1 = await repo.loadThemeSettings();
    expect(loaded1.primaryColor.value, Colors.purple.value);

    // Switching company must not inherit A's overrides.
    await SessionManager.setCompanyId(2);

    final loaded2 = await repo.loadThemeSettings();
    expect(
      loaded2.primaryColor.value,
      ThemeSettings.defaultSettings.primaryColor.value,
    );

    // Persisted per company: switching back restores the override.
    await SessionManager.setCompanyId(1);

    final loaded1Again = await repo.loadThemeSettings();
    expect(loaded1Again.primaryColor.value, Colors.purple.value);

    // Reset clears overrides only for that company.
    await repo.resetToDefault();

    final afterReset = await repo.loadThemeSettings();
    expect(afterReset, ThemeSettings.defaultSettings);

    await SessionManager.setCompanyId(2);
    final company2Unchanged = await repo.loadThemeSettings();
    expect(company2Unchanged, ThemeSettings.defaultSettings);
  });
}
