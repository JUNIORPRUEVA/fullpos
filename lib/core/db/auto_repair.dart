import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../backup/backup_paths.dart';
import '../backup/backup_service.dart';
import '../debug/loader_watchdog.dart';
import 'app_db.dart';
import 'database_manager.dart';

class AutoRepair {
  AutoRepair._();

  static final AutoRepair instance = AutoRepair._();

  Future<void>? _inFlight;

  Future<void> ensureDbHealthy({required String reason}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _ensureImpl(reason: reason);
    _inFlight = future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return _inFlight!;
  }

  Future<void> resetWalShmIfNeeded({
    String? reason,
    bool reopenAfter = true,
  }) async {
    final dbPath = await AppDb.databasePath();
    await _log(
      'resetWalShmIfNeeded start reason=${reason ?? 'unknown'} dbPath=$dbPath',
    );

    // Cerrar handle principal para poder borrar WAL/SHM sin carreras.
    await DatabaseManager.instance.close(reason: 'auto_repair_wal_reset');

    await _deleteIfExists(File('$dbPath-wal'));
    await _deleteIfExists(File('$dbPath-shm'));

    // Reabrir para que las siguientes operaciones usen un handle válido.
    if (reopenAfter) {
      try {
        await DatabaseManager.instance.reopen(reason: 'auto_repair_wal_reset');
      } catch (e) {
        await _log('resetWalShmIfNeeded reopen failed error=$e');
      }
    }
    await _log('resetWalShmIfNeeded done');
  }

  Future<bool> restoreLatestBackup({String? reason}) async {
    await _log('restoreLatestBackup start reason=${reason ?? 'unknown'}');
    try {
      final backups = await BackupService.instance.listBackups();
      final zips = backups.whereType<File>().toList(growable: false);
      if (zips.isEmpty) {
        await _log('restoreLatestBackup: no backups found');
        return false;
      }

      // Ya viene ordenado desc por lastModified en BackupService.listBackups().
      for (final zip in zips) {
        final path = zip.path;
        await _log('restoreLatestBackup: trying $path');
        final result = await BackupService.instance.restoreBackup(
          zipPath: path,
          maxWait: const Duration(seconds: 12),
          notes: 'AUTO_REPAIR ${reason ?? ''}'.trim(),
          recordHistory: false,
          reopenDbAfter: false,
        );
        await _log(
          'restoreLatestBackup: result ok=${result.ok} msgDev=${result.messageDev}',
        );
        if (result.ok) {
          await _log('restoreLatestBackup done (success)');
          return true;
        }
      }

      await _log('restoreLatestBackup done (no valid backups)');
      return false;
    } catch (e, st) {
      await _log('restoreLatestBackup error=$e\n$st');
      return false;
    }
  }

  Future<void> _ensureImpl({required String reason}) async {
    final watchdog = LoaderWatchdog.start(stage: 'auto_repair');
    if (kDebugMode) {
      // ignore: avoid_print
      print('[AUTO-REPAIR] ensureDbHealthy reason=$reason');
    }

    final dbPath = await AppDb.databasePath();
    watchdog.step('auto_repair:start');
    await _log('ensureDbHealthy start reason=$reason dbPath=$dbPath');

    // 1) Backup inmediato (no zip, solo copia rápida de archivos DB).
    watchdog.step('auto_repair:safety_backup');
    await _createImmediateSafetyBackup(dbPath, reason: reason);

    // 2) WAL reset primero (requisito).
    watchdog.step('auto_repair:wal_reset');
    await resetWalShmIfNeeded(reason: reason, reopenAfter: false);

    // 3) Verificar integridad.
    watchdog.step('auto_repair:quick_check');
    final quickOk = await _pragmaCheckOk(dbPath, 'quick_check');
    await _log('PRAGMA quick_check ok=$quickOk');
    if (quickOk) {
      await _log('ensureDbHealthy done (quick_check ok)');
      watchdog.dispose();
      return;
    }

    watchdog.step('auto_repair:integrity_check');
    final integrityOk = await _pragmaCheckOk(dbPath, 'integrity_check');
    await _log('PRAGMA integrity_check ok=$integrityOk');
    if (integrityOk) {
      await _log('ensureDbHealthy done (integrity_check ok)');
      watchdog.dispose();
      return;
    }

    // 4) Si sigue mal: renombrar corrupto y restaurar backup válido.
    watchdog.step('auto_repair:restore_latest');
    await _log(
      'integrity failed: renaming corrupted db and attempting restore',
    );
    await _renameCorrupted(dbPath);
    final restored = await restoreLatestBackup(reason: reason);
    if (!restored) {
      await _log('ensureDbHealthy: restoreLatestBackup failed (no backups)');
    }

    // Reabrir handle para callers.
    try {
      await DatabaseManager.instance.reopen(reason: 'auto_repair_post_restore');
    } catch (e, st) {
      await _log('ensureDbHealthy reopen failed error=$e\n$st');
    }
    await _log('ensureDbHealthy done restored=$restored');
    watchdog.dispose();
  }

  Future<void> _createImmediateSafetyBackup(
    String dbPath, {
    required String reason,
  }) async {
    try {
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        await _log('safety backup skipped (db missing)');
        return;
      }

      final baseDir = await BackupPaths.backupsBaseDir();
      final stamp = _timestamp();
      final safeBaseName = _sanitizeReason(reason);
      final outBase = p.join(
        baseDir.path,
        'auto_repair_before_${stamp}_$safeBaseName',
      );

      await dbFile.copy('$outBase.db');

      final wal = File('$dbPath-wal');
      if (await wal.exists()) {
        await wal.copy('$outBase.db-wal');
      }
      final shm = File('$dbPath-shm');
      if (await shm.exists()) {
        await shm.copy('$outBase.db-shm');
      }

      await _log('safety backup created base=$outBase');
    } catch (e) {
      await _log('safety backup error=$e');
    }
  }

  Future<bool> _pragmaCheckOk(String dbPath, String pragma) async {
    Database? db;
    try {
      // Nota: en WAL, conexiones readOnly pueden fallar (requiere -shm).
      // Abrimos en modo normal pero sin reutilizar instancia para evitar interferencias.
      db = await openDatabase(dbPath, readOnly: false, singleInstance: false);
      final rows = await db.rawQuery('PRAGMA $pragma;');
      if (rows.isEmpty) return false;
      final firstValue = rows.first.values.isNotEmpty
          ? rows.first.values.first.toString().trim().toLowerCase()
          : '';
      return firstValue == 'ok';
    } catch (e) {
      await _log('PRAGMA $pragma error=$e');
      return false;
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  Future<void> _renameCorrupted(String dbPath) async {
    await DatabaseManager.instance.close(reason: 'auto_repair_rename_corrupt');
    final stamp = _timestamp();
    final targetBase = '${dbPath}_corrupt_$stamp';
    await _safeRename(File(dbPath), targetBase);
    await _safeRename(File('$dbPath-wal'), '$targetBase-wal');
    await _safeRename(File('$dbPath-shm'), '$targetBase-shm');
    await _log('renamed corrupted db to base=$targetBase');
  }

  Future<void> _safeRename(File file, String targetPath) async {
    try {
      if (!await file.exists()) return;
      final directory = Directory(p.dirname(targetPath));
      if (!await directory.exists()) await directory.create(recursive: true);
      await file.rename(targetPath);
    } catch (e) {
      await _log('rename failed file=${file.path} target=$targetPath error=$e');
    }
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (!await file.exists()) return;
      await file.delete();
      await _log('deleted ${file.path}');
    } catch (e) {
      await _log('delete failed ${file.path} error=$e');
    }
  }

  Future<File> _logFile() async {
    final docs = await BackupPaths.documentsDir();
    final dir = Directory(p.join(docs.path, 'FULLPOS_LOGS'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'auto_repair.log'));
  }

  Future<void> _log(String message) async {
    try {
      final file = await _logFile();
      final line = '[${DateTime.now().toIso8601String()}] $message\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Nunca romper la app por logging.
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

  String _sanitizeReason(String reason) {
    return reason
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }
}
