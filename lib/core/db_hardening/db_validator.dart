import 'package:sqflite/sqflite.dart';

import '../db/tables.dart';

class DbValidationException implements Exception {
  DbValidationException(this.message);

  final String message;

  @override
  String toString() => 'DbValidationException: $message';
}

class DbValidator {
  DbValidator();

  static const Map<String, List<String>> _requiredColumns = {
    DbTables.sales: ['id', 'total', 'created_at_ms'],
    DbTables.saleItems: ['id', 'sale_id', 'qty'],
    DbTables.products: ['id', 'name', 'stock'],
    DbTables.clients: ['id', 'nombre'],
    DbTables.cashSessions: ['id', 'opened_at_ms', 'status'],
    DbTables.cashMovements: ['id', 'session_id', 'amount'],
    DbTables.users: ['id', 'username'],
    DbTables.overrideTokens: ['id', 'token_hash'],
  };

  Future<void> validate(DatabaseExecutor db) async {
    for (final entry in _requiredColumns.entries) {
      final table = entry.key;
      if (!await _tableExists(db, table)) {
        throw DbValidationException('Tabla faltante: $table');
      }
      final columns = await _getTableColumns(db, table);
      final missing = entry.value.where((column) {
        if (table == DbTables.clients && column == 'nombre') {
          return !(columns.contains('nombre') || columns.contains('name'));
        }
        return !columns.contains(column);
      });
      if (missing.isNotEmpty) {
        throw DbValidationException(
          'Columnas faltantes en $table: ${missing.join(', ')}',
        );
      }
    }
  }

  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return result.isNotEmpty;
  }

  Future<Set<String>> _getTableColumns(
    DatabaseExecutor db,
    String table,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info
        .map((row) => row['name'])
        .whereType<String>()
        .map((value) => value.toString())
        .toSet();
  }
}
