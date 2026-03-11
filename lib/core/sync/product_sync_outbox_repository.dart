import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/tables.dart';

class ProductSyncOutboxRepository {
  Future<void> enqueue({
    required int entityId,
    required String operationType,
    required Map<String, dynamic> payload,
    int priority = 50,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await AppDb.database;
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

  Future<List<Map<String, dynamic>>> listDueItems({int limit = 20}) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.query(
      DbTables.productSyncOutbox,
      where: '(status = ? OR status = ?) AND next_attempt_at_ms <= ?',
      whereArgs: ['pending', 'failed', now],
      orderBy: 'priority DESC, next_attempt_at_ms ASC, id ASC',
      limit: limit,
    );
  }

  Future<void> markSyncing(int id) async {
    final db = await AppDb.database;
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
  }

  Future<void> markSuccess(int id) async {
    final db = await AppDb.database;
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
  }

  Future<void> markFailure(
    int id, {
    required String error,
    required int retryCount,
    required Duration retryDelay,
  }) async {
    final db = await AppDb.database;
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
  }

  Future<List<Map<String, dynamic>>> listStatusRows() async {
    final db = await AppDb.database;
    return db.query(
      DbTables.productSyncOutbox,
      orderBy: 'status ASC, priority DESC, updated_at_ms DESC',
    );
  }

  Future<int> pendingCount() async {
    final db = await AppDb.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM ${DbTables.productSyncOutbox} WHERE status IN (?, ?, ?)',
      ['pending', 'failed', 'syncing'],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<int?> lastSuccessAtMs() async {
    final db = await AppDb.database;
    final rows = await db.rawQuery(
      'SELECT MAX(last_success_at_ms) AS ts FROM ${DbTables.productSyncOutbox}',
    );
    return rows.first['ts'] as int?;
  }

  Future<void> retryFailedNow() async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbTables.productSyncOutbox,
      {
        'status': 'pending',
        'next_attempt_at_ms': now,
        'locked_at_ms': null,
        'updated_at_ms': now,
      },
      where: 'status = ?',
      whereArgs: ['failed'],
    );
  }
}