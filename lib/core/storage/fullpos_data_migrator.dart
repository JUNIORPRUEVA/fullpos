import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/db_init.dart';
import 'fullpos_paths.dart';

class FullPosDataMigrator {
  FullPosDataMigrator._();

  static final FullPosDataMigrator instance = FullPosDataMigrator._();

  static const _manifestName = 'migration_manifest.json';

  bool _ran = false;

  void resetForTests() {
    _ran = false;
  }

  Future<void> migrateIfNeeded({
    String dbFileName = 'fullpos.db',
    String testDbFileName = 'fullpos_test.db',
  }) async {
    if (_ran) return;
    _ran = true;

    final root = await FullPosPaths.rootDir();
    final manifestFile = File(p.join(root.path, _manifestName));
    final actions = <Map<String, Object?>>[];

    Future<void> record(
      String action, {
      String? source,
      String? target,
      String? result,
      String? error,
    }) async {
      actions.add({
        'action': action,
        'source': source,
        'target': target,
        'result': result,
        'error': error,
        'ts': DateTime.now().toUtc().toIso8601String(),
      });
    }

    try {
      final legacy = await _legacyLocations();

      for (final name in [dbFileName, testDbFileName]) {
        await _copyFirstExistingFile(
          legacy.databaseFiles(name),
          File(await FullPosPaths.databasePath(name)),
          '$name database',
          record,
          sidecars: ['-wal', '-shm'],
        );
      }

      await _copyFirstExistingDir(
        legacy.productImageDirs,
        await FullPosPaths.productImagesDir(),
        'product images',
        record,
      );
      await _copyFirstExistingDir(
        legacy.categoryImageDirs,
        await FullPosPaths.categoryImagesDir(),
        'category images',
        record,
      );
      await _copyFirstExistingDir(
        legacy.profileImageDirs,
        await FullPosPaths.profileImagesDir(),
        'profile images',
        record,
      );
      await _copyFirstExistingDir(
        legacy.businessMediaDirs,
        await FullPosPaths.businessMediaDir(),
        'business media',
        record,
      );
      await _copyFirstExistingDir(
        legacy.backupDirs,
        await FullPosPaths.backupsDir(),
        'backups',
        record,
      );
      await _copyFirstExistingDir(
        legacy.supportLogDirs,
        await FullPosPaths.supportLogsDir(),
        'support logs',
        record,
      );
      await _copyFirstExistingFile(
        legacy.licenseFiles,
        await FullPosPaths.licenseFile(),
        'license',
        record,
      );
      await _copyFirstExistingDir(
        legacy.identityDirs,
        await FullPosPaths.identityDir(),
        'identity',
        record,
      );
      await _copyFirstExistingDir(
        legacy.updateDirs,
        await FullPosPaths.updatesDir(),
        'updates',
        record,
      );
      await _copyFirstExistingFile(
        legacy.pendingRegistrationFiles,
        File(
          p.join(
            (await FullPosPaths.dataDir()).path,
            'pending_registration_queue_v1.json',
          ),
        ),
        'pending registration queue',
        record,
      );

      await _rewriteCopiedMediaPaths(
        dbFileName: dbFileName,
        legacy: legacy,
        record: record,
      );
      await _rewriteCopiedMediaPaths(
        dbFileName: testDbFileName,
        legacy: legacy,
        record: record,
      );
      await _rewriteProfileImagePreferences(legacy: legacy, record: record);

      await _writeManifest(manifestFile, actions, status: 'success');
    } catch (e, st) {
      await record('migration_failed', result: 'failed', error: '$e\n$st');
      await _writeManifest(manifestFile, actions, status: 'failed');
      rethrow;
    }
  }

  Future<_LegacyLocations> _legacyLocations() async {
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final usesTempPaths = _isInsideTemp(docs) || _isInsideTemp(support);
    final appData = Platform.isWindows && !usesTempPaths
        ? Platform.environment['APPDATA']?.trim()
        : null;
    final localAppData = Platform.isWindows && !usesTempPaths
        ? Platform.environment['LOCALAPPDATA']?.trim()
        : null;

    return _LegacyLocations(
      docs: docs,
      support: support,
      appData: appData == null || appData.isEmpty ? null : Directory(appData),
      localAppData: localAppData == null || localAppData.isEmpty
          ? null
          : Directory(localAppData),
    );
  }

  bool _isInsideTemp(Directory directory) {
    final path = p.normalize(directory.path).toLowerCase();
    final temp = p.normalize(Directory.systemTemp.path).toLowerCase();
    return p.equals(path, temp) || p.isWithin(temp, path);
  }

  Future<void> _copyFirstExistingFile(
    List<File> sources,
    File target,
    String label,
    Future<void> Function(
      String action, {
      String? source,
      String? target,
      String? result,
      String? error,
    })
    record, {
    List<String> sidecars = const [],
  }) async {
    if (await target.exists()) {
      await record(label, target: target.path, result: 'target_exists');
      return;
    }

    for (final source in sources) {
      if (!await source.exists()) continue;
      await target.parent.create(recursive: true);
      await source.copy(target.path);
      await record(
        label,
        source: source.path,
        target: target.path,
        result: 'copied',
      );
      for (final suffix in sidecars) {
        final sourceSidecar = File('${source.path}$suffix');
        if (!await sourceSidecar.exists()) continue;
        await sourceSidecar.copy('${target.path}$suffix');
        await record(
          '$label$suffix',
          source: sourceSidecar.path,
          target: '${target.path}$suffix',
          result: 'copied',
        );
      }
      return;
    }

    await record(label, target: target.path, result: 'source_missing');
  }

  Future<void> _copyFirstExistingDir(
    List<Directory> sources,
    Directory target,
    String label,
    Future<void> Function(
      String action, {
      String? source,
      String? target,
      String? result,
      String? error,
    })
    record,
  ) async {
    await target.create(recursive: true);

    for (final source in sources) {
      if (!await source.exists()) continue;
      await _copyDirMerge(source, target);
      await record(
        label,
        source: source.path,
        target: target.path,
        result: 'merged',
      );
      return;
    }

    await record(label, target: target.path, result: 'source_missing');
  }

  Future<void> _copyDirMerge(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: source.path);
      final dest = File(p.join(target.path, rel));
      if (await dest.exists()) continue;
      await dest.parent.create(recursive: true);
      await entity.copy(dest.path);
    }
  }

  Future<void> _rewriteCopiedMediaPaths({
    required String dbFileName,
    required _LegacyLocations legacy,
    required Future<void> Function(
      String action, {
      String? source,
      String? target,
      String? result,
      String? error,
    })
    record,
  }) async {
    final dbFile = File(await FullPosPaths.databasePath(dbFileName));
    if (!await dbFile.exists()) return;

    DbInit.ensureInitialized();
    Database? db;
    try {
      db = await openDatabase(
        dbFile.path,
        singleInstance: false,
        readOnly: false,
      );

      final productTarget = await FullPosPaths.productImagesDir();
      for (final source in legacy.productImageDirs) {
        await _rewritePathPrefix(
          db,
          table: 'products',
          column: 'image_path',
          oldDir: source,
          newDir: productTarget,
        );
      }

      final categoryTarget = await FullPosPaths.categoryImagesDir();
      for (final source in legacy.categoryImageDirs) {
        await _rewritePathPrefix(
          db,
          table: 'categories',
          column: 'image_path',
          oldDir: source,
          newDir: categoryTarget,
        );
      }

      final businessTarget = await FullPosPaths.businessMediaDir();
      for (final source in legacy.businessMediaDirs) {
        await _rewritePathPrefix(
          db,
          table: 'business_settings',
          column: 'logo_path',
          oldDir: source,
          newDir: businessTarget,
        );
      }

      await record(
        'rewrite media paths $dbFileName',
        target: dbFile.path,
        result: 'ok',
      );
    } catch (e) {
      await record(
        'rewrite media paths $dbFileName',
        target: dbFile.path,
        result: 'failed',
        error: e.toString(),
      );
    } finally {
      await db?.close();
    }
  }

  Future<void> _rewritePathPrefix(
    Database db, {
    required String table,
    required String column,
    required Directory oldDir,
    required Directory newDir,
  }) async {
    if (!await oldDir.exists()) return;
    final oldPrefix = p.normalize(oldDir.path);
    final rows = await db.query(
      table,
      columns: ['id', column],
      where: "$column IS NOT NULL AND TRIM($column) != ''",
    );
    for (final row in rows) {
      final id = row['id'];
      final raw = row[column]?.toString();
      if (id == null || raw == null || raw.trim().isEmpty) continue;
      final normalized = p.normalize(raw);
      final isInside =
          p.equals(normalized, oldPrefix) || p.isWithin(oldPrefix, normalized);
      if (!isInside) continue;
      final rel = p.relative(normalized, from: oldPrefix);
      final replacement = p.join(newDir.path, rel);
      await db.update(
        table,
        {column: replacement},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _rewriteProfileImagePreferences({
    required _LegacyLocations legacy,
    required Future<void> Function(
      String action, {
      String? source,
      String? target,
      String? result,
      String? error,
    })
    record,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final target = await FullPosPaths.profileImagesDir();
      var changed = 0;
      for (final key in prefs.getKeys()) {
        if (!key.startsWith('profile_image_path:')) continue;
        final raw = prefs.getString(key);
        if (raw == null || raw.trim().isEmpty) continue;
        final normalized = p.normalize(raw);
        for (final source in legacy.profileImageDirs) {
          final oldPrefix = p.normalize(source.path);
          final isInside =
              p.equals(normalized, oldPrefix) ||
              p.isWithin(oldPrefix, normalized);
          if (!isInside) continue;
          final rel = p.relative(normalized, from: oldPrefix);
          await prefs.setString(key, p.join(target.path, rel));
          changed++;
          break;
        }
      }
      await record(
        'rewrite profile image preferences',
        result: 'changed=$changed',
      );
    } catch (e) {
      await record(
        'rewrite profile image preferences',
        result: 'failed',
        error: e.toString(),
      );
    }
  }

  Future<void> _writeManifest(
    File manifestFile,
    List<Map<String, Object?>> actions, {
    required String status,
  }) async {
    final payload = {
      'status': status,
      'root': (await FullPosPaths.rootDir()).path,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'actions': actions,
    };
    await manifestFile.parent.create(recursive: true);
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }
}

class _LegacyLocations {
  const _LegacyLocations({
    required this.docs,
    required this.support,
    required this.appData,
    required this.localAppData,
  });

  final Directory docs;
  final Directory support;
  final Directory? appData;
  final Directory? localAppData;

  List<File> databaseFiles(String name) => [
    File(p.join(docs.path, name)),
    File(p.join(support.path, name)),
  ];

  List<Directory> get productImageDirs => [
    Directory(p.join(docs.path, 'product_images')),
  ];

  List<Directory> get categoryImageDirs => [
    Directory(p.join(docs.path, 'category_images')),
  ];

  List<Directory> get profileImageDirs => [
    Directory(p.join(docs.path, 'profile_images')),
  ];

  List<Directory> get businessMediaDirs => [
    Directory(p.join(docs.path, 'fullpos')),
  ];

  List<Directory> get backupDirs => [
    Directory(p.join(docs.path, 'FULLPOS_BACKUPS')),
    Directory(p.join(support.path, 'FULLPOS_BACKUPS')),
  ];

  List<Directory> get supportLogDirs => [
    Directory(p.join(docs.path, 'FULLPOS_LOGS')),
  ];

  List<File> get licenseFiles => [
    if (appData != null)
      File(p.join(appData!.path, FullPosPaths.legacyAppDirName, 'license.dat')),
    File(p.join(support.path, FullPosPaths.legacyAppDirName, 'license.dat')),
  ];

  List<Directory> get identityDirs => [
    Directory(p.join(support.path, 'identity')),
    Directory(p.join(docs.path, 'FULLPOS_BACKUPS', 'identity')),
  ];

  List<Directory> get updateDirs => [
    if (localAppData != null)
      Directory(
        p.join(localAppData!.path, FullPosPaths.legacyAppDirName, 'updates'),
      ),
  ];

  List<File> get pendingRegistrationFiles => [
    File(
      p.join(
        support.path,
        FullPosPaths.legacyAppDirName,
        'pending_registration_queue_v1.json',
      ),
    ),
  ];
}
