import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../debug/loader_watchdog.dart';
import '../db/app_db.dart';
import '../db/database_manager.dart';
import 'db_logger.dart';
import 'db_preflight.dart';
import 'db_repair.dart';

class DbHardening {
  DbHardening._();

  static final DbHardening instance = DbHardening._();

  final _preflight = DbPreflight();

  // Serialize DB operations that go through DbHardening.
  // This reduces "database is locked" stalls on desktop/FFI when multiple
  // screens fire queries concurrently (e.g. rapid navigation, smoke tests).
  Future<void> _serial = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _serial = _serial.catchError((_) {}).then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> preflight() => _preflight.run();

  Future<T> runDbSafe<T>(
    Future<T> Function() action, {
    String stage = 'db_operation',
  }) async {
    return _enqueue(() async {
      final watchdog = LoaderWatchdog.start(stage: stage);
      try {
        var attempts = 0;
        while (true) {
          try {
            return await action();
          } on DatabaseException catch (error, trace) {
            final message = error.toString().toLowerCase();
            if (_isLockError(message) && attempts < 3) {
              attempts++;
              await Future.delayed(Duration(milliseconds: 100 * attempts));
              continue;
            }

            final repaired = await DbRepair.instance.tryFix(error, trace);
            if (repaired && attempts < 1) {
              attempts++;
              continue;
            }

            if (_isClosedError(message) && attempts < 2) {
              // Si el handle fue cerrado inesperadamente, reintentar con un handle válido.
              // Importante: NO cerrar agresivamente aquí (puede afectar otras operaciones).
              attempts++;
              await DatabaseManager.instance.reopen(
                reason: 'db_hardening_closed',
              );
              continue;
            }

            await DbLogger.instance.log(
              stage: stage,
              status: 'error',
              detail: error.toString(),
              schemaVersion: AppDb.schemaVersion,
            );
            rethrow;
          }
        }
      } finally {
        watchdog.dispose();
      }
    });
  }

  bool _isLockError(String message) {
    if (message.contains('database is locked')) return true;
    // Variantes típicas en sqflite/sqflite_ffi.
    if (message.contains('sqlite_busy')) return true;
    if (message.contains('database is busy')) return true;
    if (message.contains('sqlitexception(5)')) return true;
    if (message.contains('sqlite error 5')) return true;
    if (message.contains('code 5') &&
        (message.contains('busy') || message.contains('locked'))) {
      return true;
    }
    return false;
  }

  bool _isClosedError(String message) =>
      message.contains('database_closed') ||
      message.contains('database is closed');
}
