import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../backup/backup_paths.dart';

class DbBackup {
  DbBackup._();

  static final DbBackup instance = DbBackup._();

  static const int _maxBackups = 10;
  static const String _backupDirName = 'backups';

  Future<Directory> get _baseDir async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, _backupDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> createBackup(File dbFile, {String? reason}) async {
    if (!await dbFile.exists()) return;
    final baseDir = await _baseDir;
    final name = 'fullpos_db_${_timestamp()}${reason != null ? '_$reason' : ''}.sqlite';
    final target = File(p.join(baseDir.path, name));
    await target.parent.create(recursive: true);
    await dbFile.copy(target.path);
    await _pruneBackups(baseDir);
  }

  Future<void> _pruneBackups(Directory dir) async {
    final entries = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.sqlite')) {
        entries.add(entity);
      }
    }
    entries.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    for (var i = _maxBackups; i < entries.length; i++) {
      try {
        await entries[i].delete();
      } catch (_) {
        // Ignorar.
      }
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$y$m${d}_$h$min$s';
  }

  Future<String> getDatabasePath() => BackupPaths.databaseFilePath();
}
