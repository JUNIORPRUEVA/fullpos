import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'fiscal_receipt_models.dart';

class FiscalReceiptRepository {
  FiscalReceiptRepository._();

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.ncfBooks} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        series TEXT,
        from_n INTEGER NOT NULL DEFAULT 1,
        to_n INTEGER NOT NULL DEFAULT 1,
        next_n INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        expires_at_ms INTEGER,
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DbTables.customersNcfUsage} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        ncf_book_id INTEGER NOT NULL,
        ncf_full TEXT NOT NULL UNIQUE,
        created_at_ms INTEGER NOT NULL
      )
    ''');

    await _addColumnIfMissing(db, DbTables.appSettings, 'fiscal_enabled_default',
        'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
      db,
      DbTables.appSettings,
      'default_ncf_book_id',
      'INTEGER',
    );
    await _addColumnIfMissing(db, DbTables.ncfBooks, 'name', 'TEXT');
    await _addColumnIfMissing(db, DbTables.ncfBooks, 'code', 'TEXT');
    await _addColumnIfMissing(db, DbTables.ncfBooks, 'prefix', 'TEXT');
    await _addColumnIfMissing(
      db,
      DbTables.ncfBooks,
      'start_number',
      'INTEGER',
    );
    await _addColumnIfMissing(db, DbTables.ncfBooks, 'end_number', 'INTEGER');
    await _addColumnIfMissing(db, DbTables.ncfBooks, 'next_number', 'INTEGER');
    await _addColumnIfMissing(
      db,
      DbTables.ncfBooks,
      'requires_customer_tax_id',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      DbTables.ncfBooks,
      'requires_customer_name',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      DbTables.ncfBooks,
      'allow_final_consumer',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      DbTables.ncfBooks,
      'is_default',
      'INTEGER NOT NULL DEFAULT 0',
    );

    await _addColumnIfMissing(
      db,
      DbTables.customersNcfUsage,
      'sequence_number',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      DbTables.customersNcfUsage,
      'customer_id',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      DbTables.customersNcfUsage,
      'customer_name',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbTables.customersNcfUsage,
      'customer_tax_id',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbTables.customersNcfUsage,
      'voided_at_ms',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      DbTables.customersNcfUsage,
      'void_reason',
      'TEXT',
    );

    await _addColumnIfMissing(db, DbTables.sales, 'fiscal_enabled',
        'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, DbTables.sales, 'ncf_full', 'TEXT');
    await _addColumnIfMissing(db, DbTables.sales, 'ncf_type', 'TEXT');
    await _addColumnIfMissing(
      db,
      DbTables.sales,
      'fiscal_receipt_type_id',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      DbTables.sales,
      'fiscal_receipt_name',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbTables.sales,
      'fiscal_receipt_prefix',
      'TEXT',
    );
    await _addColumnIfMissing(
      db,
      DbTables.sales,
      'fiscal_sequence_number',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      DbTables.sales,
      'fiscal_receipt_expiration_date_ms',
      'INTEGER',
    );

    await db.execute('''
      UPDATE ${DbTables.ncfBooks}
      SET
        code = COALESCE(NULLIF(code, ''), type),
        prefix = COALESCE(NULLIF(prefix, ''), NULLIF(series, ''), type),
        name = COALESCE(NULLIF(name, ''), type),
        start_number = COALESCE(start_number, from_n),
        end_number = COALESCE(end_number, to_n),
        next_number = COALESCE(next_number, next_n)
    ''');
  }

  static Future<FiscalReceiptSettingsModel> getSettings() async {
    final db = await AppDb.database;
    await ensureSchema(db);
    final rows = await db.query(DbTables.appSettings, limit: 1);
    if (rows.isEmpty) {
      return const FiscalReceiptSettingsModel(enabled: false);
    }
    final row = rows.first;
    return FiscalReceiptSettingsModel(
      enabled: (row['fiscal_enabled_default'] as int? ?? 0) == 1,
      defaultReceiptTypeId: row['default_ncf_book_id'] as int?,
    );
  }

  static Future<void> saveSettings(FiscalReceiptSettingsModel settings) async {
    final db = await AppDb.database;
    await ensureSchema(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(DbTables.appSettings, limit: 1);
    final values = {
      'fiscal_enabled_default': settings.enabled ? 1 : 0,
      'default_ncf_book_id': settings.defaultReceiptTypeId,
      'updated_at_ms': now,
    };
    if (rows.isEmpty) {
      await db.insert(DbTables.appSettings, values);
    } else {
      await db.update(
        DbTables.appSettings,
        values,
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }

  static Future<List<FiscalReceiptTypeModel>> getAllTypes() async {
    final db = await AppDb.database;
    await ensureSchema(db);
    final rows = await db.query(
      DbTables.ncfBooks,
      where: 'deleted_at_ms IS NULL',
      orderBy: 'is_active DESC, is_default DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(FiscalReceiptTypeModel.fromMap).toList();
  }

  static Future<List<FiscalReceiptTypeModel>> getActiveTypes() async {
    final types = await getAllTypes();
    return types.where((type) => type.isAvailable).toList(growable: false);
  }

  static Future<FiscalReceiptTypeModel?> getTypeById(int id) async {
    final db = await AppDb.database;
    await ensureSchema(db);
    final rows = await db.query(
      DbTables.ncfBooks,
      where: 'id = ? AND deleted_at_ms IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : FiscalReceiptTypeModel.fromMap(rows.first);
  }

  static Future<FiscalReceiptTypeModel?> getDefaultType() async {
    final settings = await getSettings();
    final defaultId = settings.defaultReceiptTypeId;
    if (defaultId != null) {
      final type = await getTypeById(defaultId);
      if (type != null && type.isAvailable) return type;
    }
    final active = await getActiveTypes();
    final marked = active.where((type) => type.isDefault);
    return marked.isNotEmpty ? marked.first : (active.isEmpty ? null : active.first);
  }

  static Future<int> saveType(FiscalReceiptTypeModel type) async {
    _validateType(type);
    final db = await AppDb.database;
    await ensureSchema(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _validateNoConflict(db, type);
    final values = type
        .copyWith(
          createdAtMs: type.createdAtMs == 0 ? now : type.createdAtMs,
          updatedAtMs: now,
        )
        .toMap();
    if (type.id == null) {
      return db.insert(DbTables.ncfBooks, values);
    }
    await db.update(
      DbTables.ncfBooks,
      values..remove('id'),
      where: 'id = ?',
      whereArgs: [type.id],
    );
    return type.id!;
  }

  static Future<void> setDefaultType(int? id) async {
    final db = await AppDb.database;
    await ensureSchema(db);
    await db.transaction((txn) async {
      await txn.update(DbTables.ncfBooks, {'is_default': 0});
      if (id != null) {
        await txn.update(
          DbTables.ncfBooks,
          {'is_default': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      final rows = await txn.query(DbTables.appSettings, limit: 1);
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = {'default_ncf_book_id': id, 'updated_at_ms': now};
      if (rows.isEmpty) {
        await txn.insert(DbTables.appSettings, {
          'fiscal_enabled_default': 0,
          ...values,
        });
      } else {
        await txn.update(
          DbTables.appSettings,
          values,
          where: 'id = ?',
          whereArgs: [rows.first['id']],
        );
      }
    });
  }

  static Future<void> softDeleteType(int id) async {
    final db = await AppDb.database;
    await ensureSchema(db);
    final usage = await db.query(
      DbTables.customersNcfUsage,
      columns: ['id'],
      where: 'ncf_book_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (usage.isEmpty) {
      await db.delete(DbTables.ncfBooks, where: 'id = ?', whereArgs: [id]);
    } else {
      await db.update(
        DbTables.ncfBooks,
        {'is_active': 0, 'deleted_at_ms': now, 'updated_at_ms': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getUsageHistory(int typeId) async {
    final db = await AppDb.database;
    await ensureSchema(db);
    return db.query(
      DbTables.customersNcfUsage,
      where: 'ncf_book_id = ?',
      whereArgs: [typeId],
      orderBy: 'created_at_ms DESC',
      limit: 200,
    );
  }

  static Future<FiscalReceiptAssignment> reserveNextReceiptForSale({
    required DatabaseExecutor txn,
    required int receiptTypeId,
    required int saleId,
    int? customerId,
    String? customerName,
    String? customerTaxId,
  }) async {
    await ensureSchema(txn);
    final rows = await txn.query(
      DbTables.ncfBooks,
      where: 'id = ? AND deleted_at_ms IS NULL',
      whereArgs: [receiptTypeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('El comprobante seleccionado no existe.');
    }
    final type = FiscalReceiptTypeModel.fromMap(rows.first);
    _validateTypeAvailability(type);
    _validateCustomer(type, customerName: customerName, customerTaxId: customerTaxId);

    final receiptNumber = type.nextReceiptNumber;
    final sequence = type.nextNumber;
    final now = DateTime.now().millisecondsSinceEpoch;

    await txn.update(
      DbTables.ncfBooks,
      {
        'next_n': sequence + 1,
        'next_number': sequence + 1,
        'updated_at_ms': now,
      },
      where: 'id = ? AND next_n = ?',
      whereArgs: [receiptTypeId, sequence],
    );
    await txn.insert(DbTables.customersNcfUsage, {
      'sale_id': saleId,
      'ncf_book_id': receiptTypeId,
      'ncf_full': receiptNumber,
      'sequence_number': sequence,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_tax_id': customerTaxId,
      'created_at_ms': now,
    });
    await txn.update(
      DbTables.sales,
      {
        'fiscal_enabled': 1,
        'ncf_full': receiptNumber,
        'ncf_type': type.code,
        'fiscal_receipt_type_id': receiptTypeId,
        'fiscal_receipt_name': type.name,
        'fiscal_receipt_prefix': type.prefix,
        'fiscal_sequence_number': sequence,
        'fiscal_receipt_expiration_date_ms': type.expiresAtMs,
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    return FiscalReceiptAssignment(
      receiptTypeId: receiptTypeId,
      receiptName: type.name,
      receiptCode: type.code,
      receiptPrefix: type.prefix,
      receiptNumber: receiptNumber,
      sequenceNumber: sequence,
      expirationDateMs: type.expiresAtMs,
    );
  }

  static void _validateType(FiscalReceiptTypeModel type) {
    if (type.name.trim().isEmpty) {
      throw ArgumentError('El nombre del comprobante es requerido.');
    }
    if (type.code.trim().isEmpty) {
      throw ArgumentError('El código fiscal es requerido.');
    }
    if (type.prefix.trim().isEmpty) {
      throw ArgumentError('El prefijo es requerido.');
    }
    if (type.endNumber < type.startNumber) {
      throw ArgumentError('La secuencia final debe ser mayor o igual a la inicial.');
    }
    if (type.nextNumber < type.startNumber) {
      throw ArgumentError('El próximo número no puede ser menor que la secuencia inicial.');
    }
    if (type.nextNumber > type.endNumber + 1) {
      throw ArgumentError('El próximo número no puede superar la secuencia final.');
    }
  }

  static void _validateTypeAvailability(FiscalReceiptTypeModel type) {
    if (!type.isActive || type.deletedAtMs != null) {
      throw StateError('El comprobante seleccionado está inactivo.');
    }
    if (type.isExpired) {
      throw StateError('El comprobante seleccionado está vencido.');
    }
    if (type.isExhausted) {
      throw StateError('La secuencia del comprobante está agotada.');
    }
  }

  static void _validateCustomer(
    FiscalReceiptTypeModel type, {
    String? customerName,
    String? customerTaxId,
  }) {
    final taxId = (customerTaxId ?? '').trim();
    final name = (customerName ?? '').trim();
    if (type.requiresCustomerTaxId && taxId.isEmpty) {
      throw StateError('Este comprobante requiere cliente con RNC/Cédula.');
    }
    if (type.requiresCustomerName && name.isEmpty) {
      throw StateError('Este comprobante requiere nombre fiscal del cliente.');
    }
    if (!type.allowFinalConsumer && taxId.isEmpty) {
      throw StateError('Este comprobante no permite consumidor final.');
    }
  }

  static Future<void> _validateNoConflict(
    DatabaseExecutor db,
    FiscalReceiptTypeModel type,
  ) async {
    final rows = await db.query(
      DbTables.ncfBooks,
      columns: ['id'],
      where:
          'UPPER(TRIM(type)) = UPPER(TRIM(?)) AND UPPER(TRIM(series)) = UPPER(TRIM(?)) AND is_active = 1 AND deleted_at_ms IS NULL ${type.id == null ? '' : 'AND id <> ?'}',
      whereArgs: [
        type.code,
        type.prefix,
        if (type.id != null) type.id,
      ],
      limit: 1,
    );
    if (rows.isNotEmpty && type.isActive) {
      throw ArgumentError('Ya existe un comprobante activo con ese código y prefijo.');
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    if (!await _tableExists(db, table)) return;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
