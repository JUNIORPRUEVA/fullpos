import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../backup/backup_paths.dart';
import '../db/app_db.dart';
import '../db/auto_repair.dart';
import '../db/database_manager.dart';
import 'db_backup.dart';
import 'db_logger.dart';
import 'db_validator.dart';

class DbRepair {
  DbRepair._();

  static final DbRepair instance = DbRepair._();

  Future<bool> tryFix(DatabaseException error, StackTrace stackTrace) async {
    final message = error.toString().toLowerCase();
    if (message.contains('no such table') ||
        message.contains('no such column')) {
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

    // Intentar auto-reparación (restaurar último backup) antes de reconstruir.
    // Si no hay backups válidos, AutoRepair renombrará el corrupto y la DB
    // se recreará al reabrir.
    await AutoRepair.instance.ensureDbHealthy(reason: 'integrity_$result');

    // Garantizar que haya un handle abierto post-repair.
    await DatabaseManager.instance.reopen(reason: 'integrity_$result');
    await DbLogger.instance.log(
      stage: 'repair',
      status: 'integrity_auto_repaired',
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
}
