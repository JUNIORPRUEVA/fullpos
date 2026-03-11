import '../db/app_db.dart';
import '../db/tables.dart';

class SyncOutboxRepository {
  Future<void> enqueue({
    required String target,
    String? reason,
    Duration delay = Duration.zero,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = now + delay.inMilliseconds;

    final rows = await db.query(
      DbTables.syncOutbox,
      columns: ['target', 'created_at_ms'],
      where: 'target = ?',
      whereArgs: [target],
      limit: 1,
    );

    if (rows.isEmpty) {
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
      });
      return;
    }

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
  }

  Future<List<String>> listDueTargets({int limit = 10}) async {
    final db = await AppDb.database;
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
  }

  Future<void> markSyncing(String target) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbTables.syncOutbox,
      {'status': 'syncing', 'last_attempt_at_ms': now, 'updated_at_ms': now},
      where: 'target = ?',
      whereArgs: [target],
    );
  }

  Future<void> markSuccess(String target, {int? durationMs}) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
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
      where: 'target = ?',
      whereArgs: [target],
    );
  }

  Future<void> markFailure(
    String target, {
    required String error,
    required int attemptCount,
    required Duration retryDelay,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbTables.syncOutbox,
      {
        'status': 'failed',
        'attempt_count': attemptCount,
        'next_attempt_at_ms': now + retryDelay.inMilliseconds,
        'last_error': error,
        'updated_at_ms': now,
      },
      where: 'target = ?',
      whereArgs: [target],
    );
  }

  Future<int> getAttemptCount(String target) async {
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.syncOutbox,
      columns: ['attempt_count'],
      where: 'target = ?',
      whereArgs: [target],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['attempt_count'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> listStatusRows() async {
    final db = await AppDb.database;
    return db.query(DbTables.syncOutbox, orderBy: 'target ASC');
  }

  Future<void> retryAllFailedNow() async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      DbTables.syncOutbox,
      {'status': 'pending', 'next_attempt_at_ms': now, 'updated_at_ms': now},
      where: 'status = ?',
      whereArgs: ['failed'],
    );
  }
}
