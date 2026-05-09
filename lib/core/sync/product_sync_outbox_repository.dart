import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/database_manager.dart';
import '../db/tables.dart';

class ProductSyncOutboxRepository {
  Future<T> _withRecoveredDb<T>(Future<T> Function(Database db) action) async {
    Future<T> run() async {
      final db = await AppDb.database;
      return action(db);
    }

    try {
      return await run();
    } catch (error) {
      if (!_isClosedDatabaseError(error)) rethrow;
      await DatabaseManager.instance.reopen(reason: 'product_sync_outbox');
      return run();
    }
  }

  bool _isClosedDatabaseError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('database has already been closed') ||
        message.contains('database_closed') ||
        message.contains('database is closed') ||
        message.contains('bad state: this database has already been closed');
  }

  Future<void> enqueue({
    required int entityId,
    required String operationType,
    required Map<String, dynamic> payload,
    int priority = 50,
    DatabaseExecutor? executor,
  }) async {
    Future<void> run(DatabaseExecutor db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final encodedPayload = jsonEncode(payload);

      final existing = await db.query(
        DbTables.productSyncOutbox,
        columns: ['id'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['product', entityId],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert(DbTables.productSyncOutbox, {
          'entity_type': 'product',
          'entity_id': entityId,
          'operation_type': operationType,
          'payload_json': encodedPayload,
          'status': 'pending',
          'priority': priority,
          'retry_count': 0,
          'next_attempt_at_ms': now,
          'locked_at_ms': null,
          'last_attempt_at_ms': null,
          'last_success_at_ms': null,
          'last_error': null,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
        return;
      }

      await db.update(
        DbTables.productSyncOutbox,
        {
          'operation_type': operationType,
          'payload_json': encodedPayload,
          'status': 'pending',
          'priority': priority,
          'next_attempt_at_ms': now,
          'locked_at_ms': null,
          'last_error': null,
          'updated_at_ms': now,
        },
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['product', entityId],
      );
    }

    if (executor != null) {
      await run(executor);
      return;
    }

    await _withRecoveredDb((db) => run(db));
  }

  Future<List<Map<String, dynamic>>> listDueItems({int limit = 20}) async {
    return _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return db.query(
        DbTables.productSyncOutbox,
        where: '(status = ? OR status = ?) AND next_attempt_at_ms <= ?',
        whereArgs: ['pending', 'failed', now],
        orderBy: 'priority DESC, next_attempt_at_ms ASC, id ASC',
        limit: limit,
      );
    });
  }

  Future<void> markSyncing(int id) async {
    await _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        DbTables.productSyncOutbox,
        {
          'status': 'syncing',
          'locked_at_ms': now,
          'last_attempt_at_ms': now,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> markSuccess(int id) async {
    await _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        DbTables.productSyncOutbox,
        {
          'status': 'synced',
          'retry_count': 0,
          'next_attempt_at_ms': now,
          'locked_at_ms': null,
          'last_success_at_ms': now,
          'last_error': null,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> markFailure(
    int id, {
    required String error,
    required int retryCount,
    required Duration retryDelay,
  }) async {
    await _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        DbTables.productSyncOutbox,
        {
          'status': 'failed',
          'retry_count': retryCount,
          'next_attempt_at_ms': now + retryDelay.inMilliseconds,
          'locked_at_ms': null,
          'last_error': error,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> markRejected(int id, {required String error}) async {
    await _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        DbTables.productSyncOutbox,
        {
          'status': 'rejected',
          'locked_at_ms': null,
          'last_error': error,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, dynamic>>> listStatusRows() async {
    return _withRecoveredDb(
      (db) => db.query(
        DbTables.productSyncOutbox,
        orderBy: 'status ASC, priority DESC, updated_at_ms DESC',
      ),
    );
  }

  Future<int> pendingCount() async {
    return _withRecoveredDb((db) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM ${DbTables.productSyncOutbox} WHERE status IN (?, ?, ?)',
        ['pending', 'failed', 'syncing'],
      );
      return (rows.first['count'] as int?) ?? 0;
    });
  }

  Future<int?> lastSuccessAtMs() async {
    return _withRecoveredDb((db) async {
      final rows = await db.rawQuery(
        'SELECT MAX(last_success_at_ms) AS ts FROM ${DbTables.productSyncOutbox}',
      );
      return rows.first['ts'] as int?;
    });
  }

  Future<void> retryFailedNow() async {
    await _withRecoveredDb((db) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        DbTables.productSyncOutbox,
        {
          'status': 'pending',
          'retry_count': 0,
          'next_attempt_at_ms': now,
          'locked_at_ms': null,
          'last_error': null,
          'updated_at_ms': now,
        },
        where: 'status = ?',
        whereArgs: ['failed'],
      );
    });
  }
}
