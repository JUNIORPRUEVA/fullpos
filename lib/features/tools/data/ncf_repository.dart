import 'package:sqflite/sqflite.dart';
import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'models/ncf_book_model.dart';

/// Repositorio para gestionar talonarios de NCF
class NcfRepository {
  /// Obtener todos los talonarios (activos, inactivos, no eliminados)
  Future<List<NcfBookModel>> getAll({bool? activeOnly, String? type}) async {
    final db = await AppDb.database;

    final where = <String>[];
    final whereArgs = <dynamic>[];

    // Excluir eliminados
    where.add('deleted_at_ms IS NULL');

    if (activeOnly != null) {
      where.add('is_active = ?');
      whereArgs.add(activeOnly ? 1 : 0);
    }

    if (type != null) {
      where.add('type = ?');
      whereArgs.add(type);
    }

    final results = await db.query(
      DbTables.ncfBooks,
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'created_at_ms DESC',
    );

    return results.map((map) => NcfBookModel.fromMap(map)).toList();
  }

  /// Obtener talonarios disponibles para usar en ventas
  /// (activos, no agotados, no vencidos)
  Future<List<NcfBookModel>> getAvailable({String? type}) async {
    final all = await getAll(activeOnly: true, type: type);
    final now = DateTime.now();

    return all.where((book) {
      // Debe estar activo
      if (!book.isActive) return false;

      // Debe tener números disponibles
      if (book.isExhausted) return false;

      // No debe estar vencido
      if (book.expiresAt != null && book.expiresAt!.isBefore(now)) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Obtener un talonario por ID
  Future<NcfBookModel?> getById(int id) async {
    final db = await AppDb.database;

    final results = await db.query(
      DbTables.ncfBooks,
      where: 'id = ? AND deleted_at_ms IS NULL',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return NcfBookModel.fromMap(results.first);
  }

  /// Crear un nuevo talonario
  Future<int> create(NcfBookModel book) async {
    final db = await AppDb.database;

    // Validar que no haya solapamiento de rangos
    final overlapping = await _checkOverlapping(
      db,
      type: book.type,
      series: book.series,
      fromN: book.fromN,
      toN: book.toN,
    );

    if (overlapping) {
      throw Exception(
        'Ya existe un talonario con rangos que se solapan para este tipo/serie',
      );
    }

    final id = await db.insert(DbTables.ncfBooks, book.toMap());

    return id;
  }

  /// Actualizar un talonario
  Future<void> update(NcfBookModel book) async {
    if (book.id == null) {
      throw Exception('No se puede actualizar un talonario sin ID');
    }

    final db = await AppDb.database;

    // Validar que no haya solapamiento de rangos (excluyendo el actual)
    final overlapping = await _checkOverlapping(
      db,
      type: book.type,
      series: book.series,
      fromN: book.fromN,
      toN: book.toN,
      excludeId: book.id,
    );

    if (overlapping) {
      throw Exception(
        'Ya existe un talonario con rangos que se solapan para este tipo/serie',
      );
    }

    await db.update(
      DbTables.ncfBooks,
      book.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  /// Activar/desactivar un talonario
  Future<void> toggleActive(int id) async {
    final db = await AppDb.database;
    final book = await getById(id);

    if (book == null) {
      throw Exception('Talonario no encontrado');
    }

    await db.update(
      DbTables.ncfBooks,
      {
        'is_active': book.isActive ? 0 : 1,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Eliminar un talonario (soft delete)
  Future<void> delete(int id) async {
    final db = await AppDb.database;

    // Verificar si el talonario ha sido usado
    final usage = await _checkUsage(db, id);
    if (usage > 0) {
      throw Exception(
        'No se puede eliminar un talonario que ya ha sido usado ($usage NCF emitidos)',
      );
    }

    await db.update(
      DbTables.ncfBooks,
      {
        'deleted_at_ms': DateTime.now().millisecondsSinceEpoch,
        'is_active': 0,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Consumir el siguiente NCF (incrementar next_n)
  /// Retorna el NCF completo generado
  Future<String> consumeNext(int bookId) async {
    final db = await AppDb.database;

    // Usar transacción para evitar race conditions
    return await db.transaction((txn) async {
      final results = await txn.query(
        DbTables.ncfBooks,
        where: 'id = ? AND deleted_at_ms IS NULL',
        whereArgs: [bookId],
        limit: 1,
      );
      if (results.isEmpty) {
        throw Exception('Talonario no encontrado');
      }
      final book = NcfBookModel.fromMap(results.first);

      if (!book.isActive) {
        throw Exception('El talonario está inactivo');
      }

      if (book.isExhausted) {
        throw Exception('El talonario está agotado');
      }

      if (book.expiresAt != null && book.expiresAt!.isBefore(DateTime.now())) {
        throw Exception('El talonario está vencido');
      }

      // Generar el NCF completo
      final ncfFull = book.generateFullNcf();

      // Incrementar next_n
      await txn.update(
        DbTables.ncfBooks,
        {
          'next_n': book.nextN + 1,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [bookId],
      );

      return ncfFull;
    });
  }

  /// Verificar si hay solapamiento de rangos
  Future<bool> _checkOverlapping(
    Database db, {
    required String type,
    String? series,
    required int fromN,
    required int toN,
    int? excludeId,
  }) async {
    final where = <String>['type = ?', 'deleted_at_ms IS NULL'];
    final whereArgs = <dynamic>[type];

    // Series debe coincidir (null = null, o 'A' = 'A')
    if (series != null) {
      where.add('series = ?');
      whereArgs.add(series);
    } else {
      where.add('series IS NULL');
    }

    // Excluir el ID actual si se está editando
    if (excludeId != null) {
      where.add('id != ?');
      whereArgs.add(excludeId);
    }

    // Buscar rangos que se solapen
    where.add('NOT (to_n < ? OR from_n > ?)');
    whereArgs.add(fromN);
    whereArgs.add(toN);

    final results = await db.query(
      DbTables.ncfBooks,
      where: where.join(' AND '),
      whereArgs: whereArgs,
      limit: 1,
    );

    return results.isNotEmpty;
  }

  /// Verificar cuántos NCF se han usado de este talonario
  Future<int> _checkUsage(Database db, int bookId) async {
    final results = await db.query(
      DbTables.customersNcfUsage,
      where: 'ncf_book_id = ?',
      whereArgs: [bookId],
    );

    return results.length;
  }

  /// Obtener estadísticas generales
  Future<Map<String, dynamic>> getStats() async {
    final all = await getAll();
    final active = all.where((b) => b.isActive).toList();
    final available = await getAvailable();

    return {
      'total': all.length,
      'active': active.length,
      'available': available.length,
      'exhausted': active.where((b) => b.isExhausted).length,
    };
  }
}
