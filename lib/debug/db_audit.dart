import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/backup/backup_paths.dart';
import '../core/db/app_db.dart';

Future<void> runDbAudit() async {
  if (!kDebugMode) return;

  final dbPath = await AppDb.databasePath();
  final dbFile = File(dbPath);
  final walFile = File('$dbPath-wal');
  final shmFile = File('$dbPath-shm');

  int dbSize = 0;
  DateTime? modified;
  try {
    if (await dbFile.exists()) {
      dbSize = await dbFile.length();
      modified = await dbFile.lastModified();
    }
  } catch (_) {
    // Ignorar: diagnóstico no debe romper el arranque.
  }

  Directory? backupsDir;
  int backupsCount = 0;
  try {
    backupsDir = await BackupPaths.backupsBaseDir();
    if (await backupsDir.exists()) {
      backupsCount =
          backupsDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.zip'))
              .length;
    }
  } catch (_) {
    backupsDir = null;
    backupsCount = 0;
  }

  String journalMode = 'unknown';
  String synchronous = 'unknown';
  int userVersion = -1;
  try {
    final db = await openDatabase(dbPath, readOnly: true);
    try {
      final jm = await db.rawQuery('PRAGMA journal_mode;');
      final sync = await db.rawQuery('PRAGMA synchronous;');
      final uv = await db.rawQuery('PRAGMA user_version;');

      journalMode = (jm.isNotEmpty ? (jm.first.values.first) : 'unknown').toString();
      synchronous = (sync.isNotEmpty ? (sync.first.values.first) : 'unknown').toString();
      userVersion = (uv.isNotEmpty ? (uv.first['user_version'] as int?) : null) ?? -1;
    } finally {
      await db.close();
    }
  } catch (e) {
    // Si no existe DB o no puede abrirse aún, igual reportamos lo demás.
    journalMode = 'error: $e';
  }

  // ignore: avoid_print
  print('[DB-AUDIT] dbPath="$dbPath"');
  // ignore: avoid_print
  print('[DB-AUDIT] dbExists=${dbFile.existsSync()} sizeBytes=$dbSize modified=$modified');
  // ignore: avoid_print
  print(
    '[DB-AUDIT] walExists=${walFile.existsSync()} shmExists=${shmFile.existsSync()}',
  );
  // ignore: avoid_print
  print(
    '[DB-AUDIT] backupsDir="${backupsDir?.path ?? 'unknown'}" backupsCount=$backupsCount',
  );
  // ignore: avoid_print
  print(
    '[DB-AUDIT] PRAGMA journal_mode=$journalMode synchronous=$synchronous user_version=$userVersion',
  );

  // Extra: mostrar también nombre esperado del archivo.
  // ignore: avoid_print
  print('[DB-AUDIT] dbFileName=${p.basename(dbPath)} usingTestDb=${AppDb.isUsingTestDb}');
}
