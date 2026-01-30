import '../db/app_db.dart';
import '../db/tables.dart';
import 'backup_models.dart';

class BackupRepository {
  BackupRepository._();

  static final BackupRepository instance = BackupRepository._();

  Future<void> insertHistory(BackupHistoryEntry entry) async {
    final db = await AppDb.database;
    await db.insert(DbTables.backupHistory, entry.toMap());
  }

  Future<void> updateHistory(BackupHistoryEntry entry) async {
    final db = await AppDb.database;
    final values = Map<String, dynamic>.from(entry.toMap())
      ..remove('id')
      ..remove('empresa_id')
      ..remove('created_at');
    await db.update(
      DbTables.backupHistory,
      values,
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<List<BackupHistoryEntry>> listHistory({int limit = 50}) async {
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.backupHistory,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(BackupHistoryEntry.fromMap).toList();
  }

  Future<void> insertDangerAction(DangerActionLogEntry entry) async {
    final db = await AppDb.database;
    await db.insert(DbTables.dangerActionsLog, entry.toMap());
  }

}
