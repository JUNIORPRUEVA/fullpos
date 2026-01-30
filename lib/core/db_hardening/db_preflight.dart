import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import 'db_logger.dart';
import 'db_repair.dart';
import 'db_validator.dart';

class DbPreflight {
  DbPreflight();

  final _validator = DbValidator();
  final _logger = DbLogger.instance;
  final _repair = DbRepair.instance;

  Future<void> run() async {
    const stage = 'preflight';
    final schemaVersion = AppDb.schemaVersion;
    await _logger.log(stage: stage, status: 'start', schemaVersion: schemaVersion);

    try {
      final db = await AppDb.database;
      await _applyPragmas(db);
      await AppDb.ensureSchema(db);

      try {
        await _validator.validate(db);
      } on DbValidationException catch (ex) {
        await _repair.recoverFromValidation(db, ex);
        await _validator.validate(db);
      }

      final integrity = await _checkIntegrity(db);
      if (integrity != 'ok') {
        await _repair.handleIntegrityFailure(integrity);
        await _logger.log(
          stage: stage,
          status: 'integrity_fail',
          detail: 'integrity=$integrity',
          schemaVersion: schemaVersion,
        );
        return;
      }

      await _logger.log(
        stage: stage,
        status: 'success',
        detail: 'integrity=$integrity',
        schemaVersion: schemaVersion,
      );
    } catch (error) {
      await _logger.log(
        stage: stage,
        status: 'failure',
        detail: error.toString(),
        schemaVersion: schemaVersion,
      );
      rethrow;
    }
  }

  Future<void> _applyPragmas(Database db) async {
    try {
      await db.execute('PRAGMA busy_timeout = 5000;');
    } catch (_) {}
  }

  Future<String> _checkIntegrity(Database db) async {
    try {
      final rows = await db.rawQuery('PRAGMA integrity_check;');
      if (rows.isEmpty) return 'missing';
      final first = rows.first.values.first;
      return (first?.toString() ?? '').toLowerCase();
    } catch (_) {
      return 'failed';
    }
  }
}
