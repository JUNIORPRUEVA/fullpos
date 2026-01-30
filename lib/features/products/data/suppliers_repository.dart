import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../models/supplier_model.dart';

/// Repositorio para operaciones CRUD de Suplidores
class SuppliersRepository {
  /// Obtiene todos los suplidores
  Future<List<SupplierModel>> getAll({
    bool includeInactive = false,
    bool includeDeleted = false,
  }) async {
    final db = await AppDb.database;

    String where = '';
    List<dynamic> whereArgs = [];

    if (!includeDeleted) {
      where = 'deleted_at_ms IS NULL';
    }

    if (!includeInactive && where.isNotEmpty) {
      where += ' AND is_active = 1';
    } else if (!includeInactive) {
      where = 'is_active = 1';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.suppliers,
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'name ASC',
    );

    return List.generate(maps.length, (i) => SupplierModel.fromMap(maps[i]));
  }

  /// Busca suplidores por nombre o teléfono
  Future<List<SupplierModel>> search(
    String query, {
    bool includeInactive = false,
    bool includeDeleted = false,
  }) async {
    final db = await AppDb.database;

    String where = '(name LIKE ? OR phone LIKE ?)';
    List<dynamic> whereArgs = ['%$query%', '%$query%'];

    if (!includeDeleted) {
      where += ' AND deleted_at_ms IS NULL';
    }

    if (!includeInactive) {
      where += ' AND is_active = 1';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.suppliers,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );

    return List.generate(maps.length, (i) => SupplierModel.fromMap(maps[i]));
  }

  /// Obtiene un suplidor por ID
  Future<SupplierModel?> getById(int id) async {
    final db = await AppDb.database;

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.suppliers,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return SupplierModel.fromMap(maps.first);
  }

  /// Crea un nuevo suplidor
  Future<int> create(SupplierModel supplier) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final supplierToInsert = supplier.copyWith(
      createdAtMs: now,
      updatedAtMs: now,
    );

    return await db.insert(
      DbTables.suppliers,
      supplierToInsert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Actualiza un suplidor existente
  Future<int> update(SupplierModel supplier) async {
    if (supplier.id == null) {
      throw ArgumentError('El suplidor debe tener un ID para actualizarlo');
    }

    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final supplierToUpdate = supplier.copyWith(updatedAtMs: now);

    return await db.update(
      DbTables.suppliers,
      supplierToUpdate.toMap(),
      where: 'id = ?',
      whereArgs: [supplier.id],
    );
  }

  /// Elimina lógicamente (soft delete) un suplidor
  Future<int> softDelete(int id) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.suppliers,
      {
        'deleted_at_ms': now,
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Restaura un suplidor eliminado
  Future<int> restore(int id) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.suppliers,
      {
        'deleted_at_ms': null,
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina permanentemente un suplidor
  Future<int> hardDelete(int id) async {
    final db = await AppDb.database;

    return await db.delete(
      DbTables.suppliers,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Activa o desactiva un suplidor
  Future<int> toggleActive(int id, bool isActive) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.suppliers,
      {
        'is_active': isActive ? 1 : 0,
        'updated_at_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cuenta los suplidores
  Future<int> count({
    bool includeInactive = false,
    bool includeDeleted = false,
  }) async {
    final db = await AppDb.database;

    String where = '';
    List<dynamic> whereArgs = [];

    if (!includeDeleted) {
      where = 'deleted_at_ms IS NULL';
    }

    if (!includeInactive && where.isNotEmpty) {
      where += ' AND is_active = 1';
    } else if (!includeInactive) {
      where = 'is_active = 1';
    }

    final result = await db.query(
      DbTables.suppliers,
      columns: ['COUNT(*) as count'],
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Verifica si existe un suplidor con el mismo nombre
  Future<bool> existsByName(String name, {int? excludeId}) async {
    final db = await AppDb.database;

    String where = 'name = ? AND deleted_at_ms IS NULL';
    List<dynamic> whereArgs = [name];

    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }

    final result = await db.query(
      DbTables.suppliers,
      columns: ['COUNT(*) as count'],
      where: where,
      whereArgs: whereArgs,
    );

    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }
}


