import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/database_manager.dart';
import '../db/tables.dart';

class SyncOutboxRepository {
  Future<T> _withRecoveredDb<T>(Future<T> Function(Database db) action) async {
    Future<T> run() async {
      final db = await AppDb.database;
      return action(db);
    }

    try {
      return await run();
    } catch (error) {
      if (!_isClosedDatabaseError(error)) rethrow;
      await DatabaseManager.instance.reopen(reason: 'sync_outbox');
      return run();
    }
  }

  bool _isClosedDatabaseError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('database has already been closed') ||
        message.contains('database_closed') ||
        message.contains('bad state: this database has already been closed');
  }

  Future<void> enqueue({
    required String target,
    String? reason,
    Duration delay = Duration.zero,
  }) async {
    await _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final next = now + delay.inMilliseconds;

      // INSERT OR IGNORE crea la fila si no existe; si ya existe no hace nada.
      // El UPDATE posterior aplica siempre (nueva fila o existente), eliminando
      // la race condition en llamadas concurrentes.
      await db.insert(DbTables.syncOutbox, {
        'target': target,
        'status': 'pending',
        'attempt_count': 0,
        'next_attempt_at_ms': next,
        'last_attempt_at_ms': null,
        'last_success_at_ms': null,
        'last_error': null,
        'reason': reason,
        'created_at_ms': now,
        'updated_at_ms': now,
        'last_duration_ms': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await db.update(
        DbTables.syncOutbox,
        {
          'status': 'pending',
          'next_attempt_at_ms': next,
          'reason': reason,
          'updated_at_ms': now,
        },
        where: 'target = ?',
        whereArgs: [target],
      );
    });
  }

  Future<List<String>> listDueTargets({int limit = 10}) async {
    return _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await db.query(
        DbTables.syncOutbox,
        columns: ['target'],
        where: '(status = ? OR status = ?) AND next_attempt_at_ms <= ?',
        whereArgs: ['pending', 'failed', now],
        orderBy: 'next_attempt_at_ms ASC',
        limit: limit,
      );
      return rows
          .map((row) => row['target'])
          .whereType<String>()
          .toList(growable: false);
    });
  }

  Future<int> markSyncing(String target) async {
    return _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        DbTables.syncOutbox,
        {'status': 'syncing', 'last_attempt_at_ms': now, 'updated_at_ms': now},
        where: 'target = ?',
        whereArgs: [target],
      );
      return now;
    });
  }

  Future<bool> markSuccess(String target, {int? durationMs}) async {
    return _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final changed = await db.update(
        DbTables.syncOutbox,
        {
          'status': 'synced',
          'attempt_count': 0,
          'next_attempt_at_ms': now,
          'last_success_at_ms': now,
          'last_error': null,
          'updated_at_ms': now,
          if (durationMs != null) 'last_duration_ms': durationMs,
        },
        where: 'target = ? AND status = ?',
        whereArgs: [target, 'syncing'],
      );
      return changed > 0;
    });
  }

  Future<bool> markFailure(
    String target, {
    required String error,
    required int attemptCount,
    required Duration retryDelay,
  }) async {
    return _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final changed = await db.update(
        DbTables.syncOutbox,
        {
          'status': 'failed',
          'attempt_count': attemptCount,
          'next_attempt_at_ms': now + retryDelay.inMilliseconds,
          'last_error': error,
          'updated_at_ms': now,
        },
        where: 'target = ? AND status = ?',
        whereArgs: [target, 'syncing'],
      );
      return changed > 0;
    });
  }

  Future<int> getAttemptCount(String target) async {
    final rows = await _withRecoveredDb(
      (db) => db.query(
        DbTables.syncOutbox,
        columns: ['attempt_count'],
        where: 'target = ?',
        whereArgs: [target],
        limit: 1,
      ),
    );
    if (rows.isEmpty) return 0;
    return (rows.first['attempt_count'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> listStatusRows() async {
    return _withRecoveredDb(
      (db) => db.query(DbTables.syncOutbox, orderBy: 'target ASC'),
    );
  }

  Future<void> retryAllFailedNow() async {
    await _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        DbTables.syncOutbox,
        {
          'status': 'pending',
          'attempt_count': 0,
          'next_attempt_at_ms': now,
          'last_error': null,
          'updated_at_ms': now,
        },
        where: 'status = ?',
        whereArgs: ['failed'],
      );
    });
  }

  Future<void> retainTargets(Set<String> targets) async {
    if (targets.isEmpty) return;
    await _withRecoveredDb((db) async {
      final placeholders = List.filled(targets.length, '?').join(',');
      await db.delete(
        DbTables.syncOutbox,
        where: 'target NOT IN ($placeholders)',
        whereArgs: targets.toList(growable: false),
      );
    });
  }
}
