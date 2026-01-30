import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MigrationSafety {
  MigrationSafety._();

  static const String _backupsDirName = 'FULLPOS_BACKUPS';

  static Future<Directory> _baseDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _backupsDirName, 'pre_migration'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _ts() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm$ss';
  }

  static Future<Directory> createPreMigrationBackup({
    required String dbPath,
    required int oldVersion,
    required int newVersion,
  }) async {
    final base = await _baseDir();
    final name =
        'backup_before_migration_${_ts()}_v${oldVersion}_to_v$newVersion';
    final dir = Directory(p.join(base.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);

    await _copyIfExists(File(dbPath), File(p.join(dir.path, p.basename(dbPath))));
    await _copyIfExists(
      File('$dbPath-wal'),
      File(p.join(dir.path, '${p.basename(dbPath)}-wal')),
    );
    await _copyIfExists(
      File('$dbPath-shm'),
      File(p.join(dir.path, '${p.basename(dbPath)}-shm')),
    );

    return dir;
  }

  static Future<void> restorePreMigrationBackup({
    required Directory backupDir,
    required String dbPath,
  }) async {
    final baseName = p.basename(dbPath);

    final dbBackup = File(p.join(backupDir.path, baseName));
    final walBackup = File(p.join(backupDir.path, '$baseName-wal'));
    final shmBackup = File(p.join(backupDir.path, '$baseName-shm'));

    // Limpiar destino antes de restaurar.
    await _deleteIfExists(File(dbPath));
    await _deleteIfExists(File('$dbPath-wal'));
    await _deleteIfExists(File('$dbPath-shm'));

    await _copyIfExists(dbBackup, File(dbPath), requireExists: true);
    await _copyIfExists(walBackup, File('$dbPath-wal'));
    await _copyIfExists(shmBackup, File('$dbPath-shm'));
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ignorar.
    }
  }

  static Future<void> _copyIfExists(
    File from,
    File to, {
    bool requireExists = false,
  }) async {
    if (!await from.exists()) {
      if (requireExists) {
        throw FileSystemException('Backup file missing', from.path);
      }
      return;
    }
    await to.parent.create(recursive: true);
    await from.copy(to.path);
  }
}

