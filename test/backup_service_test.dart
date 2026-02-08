import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/backup/backup_models.dart';
import 'package:fullpos/core/backup/backup_paths.dart';
import 'package:fullpos/core/backup/backup_service.dart';
import 'package:fullpos/core/backup/backup_zip.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this._docsDir, this._tempDir);

  final Directory _docsDir;
  final Directory _tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsDir.path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(_docsDir.path, 'support');

  @override
  Future<String?> getTemporaryPath() async => _tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;
  late Directory tempDir;

  setUpAll(() async {
    DbInit.ensureInitialized();
    docsDir = await Directory.systemTemp.createTemp('fullpos_docs_');
    tempDir = await Directory.systemTemp.createTemp('fullpos_tmp_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir, tempDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('createBackup crea zip con db y meta', () async {
    await AppDb.resetForTests();
    await AppDb.database; // fuerza crear archivo db
    await AppDb.close();

    final result = await BackupService.instance.createBackup(
      trigger: BackupTrigger.manual,
      includeOptionalFiles: false,
      verifyIntegrity: false,
    );

    expect(result.ok, isTrue);
    expect(result.path, isNotNull);
    expect(result.sizeBytes, isNotNull);
    expect(result.checksumSha256, isNotNull);
    expect(File(result.path!).existsSync(), isTrue);

    final entries = await BackupZip.listEntries(result.path!);
    expect(entries, contains('meta/backup.json'));
    expect(entries.any((e) => e.startsWith('db/')), isTrue);
  });

  test('createBackup incluye product_images si existe', () async {
    await AppDb.resetForTests();
    await AppDb.database;
    await AppDb.close();

    final imgDir = Directory(p.join(docsDir.path, 'product_images'));
    await imgDir.create(recursive: true);
    await File(p.join(imgDir.path, 'test.png')).writeAsBytes([1, 2, 3]);

    final result = await BackupService.instance.createBackup(
      trigger: BackupTrigger.manual,
      includeOptionalFiles: true,
      verifyIntegrity: false,
    );

    expect(result.ok, isTrue);
    final entries = await BackupZip.listEntries(result.path!);
    expect(entries, contains('files/product_images/test.png'));
  });

  test('retención mantiene últimos N backups', () async {
    await BackupService.instance.setRetentionCount(2);

    await AppDb.resetForTests();
    await AppDb.database;
    await AppDb.close();

    final r1 = await BackupService.instance.createBackup(
      trigger: BackupTrigger.manual,
      verifyIntegrity: false,
    );
    expect(r1.ok, isTrue);

    final r2 = await BackupService.instance.createBackup(
      trigger: BackupTrigger.manual,
      verifyIntegrity: false,
    );
    expect(r2.ok, isTrue);

    final r3 = await BackupService.instance.createBackup(
      trigger: BackupTrigger.manual,
      verifyIntegrity: false,
    );
    expect(r3.ok, isTrue);

    final base = await BackupPaths.backupsBaseDir();
    final zips = base
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.zip'))
        .toList();
    expect(zips.length, 2);
  });
  test('verifyZipIntegrity acepta zip valido', () async {
    await AppDb.resetForTests();
    await AppDb.database;
    await AppDb.close();

    final result = await BackupService.instance.createBackup(
      trigger: BackupTrigger.manual,
      verifyIntegrity: false,
    );

    expect(result.ok, isTrue);
    final ok = await BackupService.instance.verifyZipIntegrity(
      result.path!,
      timeout: const Duration(seconds: 30),
    );
    expect(ok, isTrue);
  });

  test('verifyZipIntegrity rechaza zip corrupto', () async {
    await AppDb.resetForTests();
    await AppDb.database;
    await AppDb.close();

    final result = await BackupService.instance.createBackup(
      trigger: BackupTrigger.manual,
      verifyIntegrity: false,
    );

    expect(result.ok, isTrue);
    final corrupted = File('${result.path}.bad');
    await File(result.path!).copy(corrupted.path);
    await corrupted.writeAsBytes([1, 2, 3], mode: FileMode.writeOnly);

    final ok = await BackupService.instance.verifyZipIntegrity(
      corrupted.path,
      timeout: const Duration(seconds: 30),
    );
    expect(ok, isNot(true));
  });

  test(
    'restoreBackup rechaza checksum mismatch antes de tocar la DB',
    () async {
      await AppDb.resetForTests();
      await AppDb.database;
      await AppDb.close();

      final result = await BackupService.instance.createBackup(
        trigger: BackupTrigger.manual,
        verifyIntegrity: false,
      );
      expect(result.ok, isTrue);
      expect(result.checksumSha256, isNotNull);

      final corrupted = File('${result.path}.bad');
      await File(result.path!).copy(corrupted.path);
      await corrupted.writeAsBytes(
        [1, 2, 3],
        mode: FileMode.writeOnly,
        flush: true,
      );

      final restore = await BackupService.instance.restoreBackup(
        zipPath: corrupted.path,
        expectedChecksumSha256: result.checksumSha256,
        recordHistory: false,
      );
      expect(restore.ok, isFalse);
      expect(restore.messageDev, contains('checksum_mismatch'));
    },
  );
}
