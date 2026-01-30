import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../backup/backup_paths.dart';
import '../db/app_db.dart';
import 'db_backup.dart';
import 'db_logger.dart';
import 'db_validator.dart';

class DbRepair {
  DbRepair._();

  static final DbRepair instance = DbRepair._();

  Future<bool> tryFix(DatabaseException error, StackTrace stackTrace) async {
    final message = error.toString().toLowerCase();
    if (message.contains('no such table') || message.contains('no such column')) {
      await _repairSchema(message);
      return true;
    }
    if (message.contains('integrity') && message.contains('check')) {
      await handleIntegrityFailure('integrity_error');
      return true;
    }
    if (message.contains('malformed') ||
        message.contains('database disk image is malformed')) {
      await handleIntegrityFailure('malformed');
      return true;
    }
    return false;
  }

  Future<void> handleIntegrityFailure(String result) async {
    final dbPath = await DbBackup.instance.getDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return;

    await DbBackup.instance.createBackup(dbFile, reason: 'integrity_$result');
    await AppDb.close();

    await _renameCorruptedFiles(dbPath, 'integrity_$result');
    await AppDb.database;
    await DbLogger.instance.log(
      stage: 'repair',
      status: 'integrity_rebuilt',
      detail: 'integrity_check=$result',
      schemaVersion: AppDb.schemaVersion,
    );
  }

  Future<void> recoverFromValidation(
    DatabaseExecutor db,
    DbValidationException reason,
  ) async {
    final dbPath = await BackupPaths.databaseFilePath();
    await DbBackup.instance.createBackup(File(dbPath), reason: 'validation');
    await AppDb.ensureSchema(db);
    await DbLogger.instance.log(
      stage: 'repair',
      status: 'validation',
      detail: reason.message,
      schemaVersion: AppDb.schemaVersion,
    );
  }

  Future<void> _repairSchema(String detail) async {
    final dbPath = await DbBackup.instance.getDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return;

    await DbBackup.instance.createBackup(dbFile, reason: 'schema_fix');
    final db = await AppDb.database;
    await AppDb.ensureSchema(db);
    await DbLogger.instance.log(
      stage: 'repair',
      status: 'schema_fix',
      detail: detail,
      schemaVersion: AppDb.schemaVersion,
    );
  }

  Future<void> _renameCorruptedFiles(String dbPath, String reason) async {
    final suffix = _sanitizeReason(reason);
    final timestamp = _timestamp();
    final base = '$dbPath.corrupt_${timestamp}_$suffix';
    await _safeRename(File(dbPath), base);
    await _safeRename(File('$dbPath-wal'), '$base-wal');
    await _safeRename(File('$dbPath-shm'), '$base-shm');
  }

  Future<void> _safeRename(File file, String targetPath) async {
    try {
      if (!await file.exists()) return;
      final directory = Directory(p.dirname(targetPath));
      if (!await directory.exists()) await directory.create(recursive: true);
      await file.rename(targetPath);
    } catch (_) {
      // Ignorar errores al renombrar.
    }
  }

  String _sanitizeReason(String reason) {
    return reason
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }
}
