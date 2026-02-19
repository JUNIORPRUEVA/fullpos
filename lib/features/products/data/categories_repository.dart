import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../models/category_model.dart';

/// Repositorio para operaciones CRUD de Categorías
class CategoriesRepository {
  static String _normalizeForMatch(String value) {
    var s = value.toLowerCase().trim();
    s = s
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Upsert defensivo por nombre para importación.
  ///
  /// - Si existe (incluso soft-deleted), lo restaura y actualiza `is_active`.
  /// - Si no existe, lo inserta.
  Future<int> upsertFromImport({
    required String name,
    bool isActive = true,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('El nombre de la categoría es obligatorio');
    }

    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Normalizar por nombre (case-insensitive).
    final existing = await db.query(
      DbTables.categories,
      columns: ['id'],
      where: 'LOWER(TRIM(name)) = LOWER(TRIM(?))',
      whereArgs: [trimmed],
      limit: 1,
    );

    if (existing.isNotEmpty && existing.first['id'] != null) {
      final id = existing.first['id'] as int;
      await db.update(
        DbTables.categories,
        {
          'name': trimmed,
          'is_active': isActive ? 1 : 0,
          'deleted_at_ms': null,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    // Fallback tolerante: evitar duplicados por acentos/guiones/puntos.
    final wanted = _normalizeForMatch(trimmed);
    if (wanted.isNotEmpty) {
      final rows = await db.query(
        DbTables.categories,
        columns: ['id', 'name'],
      );
      for (final row in rows) {
        final id = row['id'] as int?;
        final name = row['name'] as String?;
        if (id == null || name == null) continue;
        if (_normalizeForMatch(name) == wanted) {
          await db.update(
            DbTables.categories,
            {
              'name': trimmed,
              'is_active': isActive ? 1 : 0,
              'deleted_at_ms': null,
              'updated_at_ms': now,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          return id;
        }
      }
    }

    return await db.insert(DbTables.categories, {
      'name': trimmed,
      'is_active': isActive ? 1 : 0,
      'deleted_at_ms': null,
      'created_at_ms': now,
      'updated_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  /// Obtiene todas las categorías activas
  Future<List<CategoryModel>> getAll({
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
      DbTables.categories,
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'name ASC',
    );

    return List.generate(maps.length, (i) => CategoryModel.fromMap(maps[i]));
  }

  /// Busca categorías por nombre
  Future<List<CategoryModel>> search(
    String query, {
    bool includeInactive = false,
    bool includeDeleted = false,
  }) async {
    final db = await AppDb.database;

    String where = 'name LIKE ?';
    List<dynamic> whereArgs = ['%$query%'];

    if (!includeDeleted) {
      where += ' AND deleted_at_ms IS NULL';
    }

    if (!includeInactive) {
      where += ' AND is_active = 1';
    }

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.categories,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );

    return List.generate(maps.length, (i) => CategoryModel.fromMap(maps[i]));
  }

  /// Obtiene una categoría por ID
  Future<CategoryModel?> getById(int id) async {
    final db = await AppDb.database;

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.categories,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return CategoryModel.fromMap(maps.first);
  }

  /// Crea una nueva categoría
  Future<int> create(CategoryModel category) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final categoryToInsert = category.copyWith(
      createdAtMs: now,
      updatedAtMs: now,
    );

    return await db.transaction((txn) async {
      await AppDb.deleteDemoCategories(txn);
      await AppDb.deleteDemoProducts(txn);
      return await txn.insert(
        DbTables.categories,
        categoryToInsert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  /// Actualiza una categoría existente
  Future<int> update(CategoryModel category) async {
    if (category.id == null) {
      throw ArgumentError('La categoría debe tener un ID para actualizarla');
    }

    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final categoryToUpdate = category.copyWith(updatedAtMs: now);

    return await db.update(
      DbTables.categories,
      categoryToUpdate.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  /// Elimina lógicamente (soft delete) una categoría
  Future<int> softDelete(int id) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await db.update(
      DbTables.categories,
      {'deleted_at_ms': now, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    await AppDb.syncDemoCatalog(db);
    return rows;
  }

  /// Elimina lógicamente (soft delete) todas las categorías no eliminadas.
  ///
  /// Se ejecuta en bloque por performance.
  Future<int> softDeleteAll() async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await db.update(DbTables.categories, {
      'deleted_at_ms': now,
      'updated_at_ms': now,
    }, where: 'deleted_at_ms IS NULL');

    await AppDb.syncDemoCatalog(db);
    return rows;
  }

  /// Restaura una categoría eliminada
  Future<int> restore(int id) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.categories,
      {'deleted_at_ms': null, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina permanentemente una categoría
  Future<int> hardDelete(int id) async {
    final db = await AppDb.database;

    final rows = await db.delete(
      DbTables.categories,
      where: 'id = ?',
      whereArgs: [id],
    );
    await AppDb.syncDemoCatalog(db);
    return rows;
  }

  /// Activa o desactiva una categoría
  Future<int> toggleActive(int id, bool isActive) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.categories,
      {'is_active': isActive ? 1 : 0, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cuenta las categorías
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
      DbTables.categories,
      columns: ['COUNT(*) as count'],
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Verifica si existe una categoría con el mismo nombre
  Future<bool> existsByName(String name, {int? excludeId}) async {
    final db = await AppDb.database;

    String where = 'name = ? AND deleted_at_ms IS NULL';
    List<dynamic> whereArgs = [name];

    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }

    final result = await db.query(
      DbTables.categories,
      columns: ['COUNT(*) as count'],
      where: where,
      whereArgs: whereArgs,
    );

    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }
}
