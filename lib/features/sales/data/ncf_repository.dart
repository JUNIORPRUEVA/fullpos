import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'ncf_book_model.dart';

/// Repositorio para gestión de talonarios NCF
class NcfRepository {
  NcfRepository._();

  /// Obtiene todos los talonarios
  static Future<List<NcfBookModel>> getAll() async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.ncfBooks,
      orderBy: 'created_at_ms DESC',
    );
    return maps.map((m) => NcfBookModel.fromMap(m)).toList();
  }

  /// Obtiene talonarios activos por tipo
  static Future<List<NcfBookModel>> getActiveByType(String ncfType) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final maps = await db.query(
      DbTables.ncfBooks,
      where: 'type = ? AND is_active = 1 AND (expires_at_ms IS NULL OR expires_at_ms >= ?)',
      whereArgs: [ncfType, now],
      orderBy: 'created_at_ms ASC',
    );
    
    return maps.map((m) => NcfBookModel.fromMap(m)).toList();
  }

  /// Consume el siguiente NCF disponible de un tipo
  /// Retorna el NCF completo (ej: B0100000001) o null si no hay disponibles
  static Future<String?> consumeNext(String type) async {
    final db = await AppDb.database;
    String? ncfFull;

    await db.transaction((txn) async {
      // Buscar talonario activo con disponibilidad
      final now = DateTime.now().millisecondsSinceEpoch;
      final maps = await txn.query(
        DbTables.ncfBooks,
        where:
            'type = ? AND is_active = 1 AND (expires_at_ms IS NULL OR expires_at_ms >= ?)',
        whereArgs: [type, now],
        orderBy: 'created_at_ms ASC',
      );
      final books = maps.map((m) => NcfBookModel.fromMap(m)).toList();
      
      for (var book in books) {
        if (book.isAvailable) {
          // Construir NCF completo
          ncfFull = book.buildNcf();
          
          // Incrementar next_n
          await txn.update(
            DbTables.ncfBooks,
            {'next_n': book.nextN + 1},
            where: 'id = ?',
            whereArgs: [book.id],
          );
          
          break;
        }
      }
    });

    return ncfFull;
  }

  static Future<String?> consumeNextForBook(int bookId) async {
    final db = await AppDb.database;
    final rows = await db.query(
      DbTables.ncfBooks,
      where: 'id = ? AND is_active = 1',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final book = NcfBookModel.fromMap(rows.first);

    final next = book.nextN;
    if (next > book.toN) return null;

    await db.update(
      DbTables.ncfBooks,
      {'next_n': next + 1, 'updated_at_ms': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [book.id],
    );

    return book.buildNcf(number: next);
  }

  /// Crea un nuevo talonario
  static Future<int> create(NcfBookModel book) async {
    final db = await AppDb.database;
    return await db.insert(DbTables.ncfBooks, book.toMap());
  }

  /// Actualiza un talonario
  static Future<int> update(NcfBookModel book) async {
    final db = await AppDb.database;
    return await db.update(
      DbTables.ncfBooks,
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  /// Desactiva un talonario
  static Future<int> deactivate(int id) async {
    final db = await AppDb.database;
    return await db.update(
      DbTables.ncfBooks,
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Obtiene el uso de NCF por cliente
  static Future<Map<String, dynamic>?> getCustomerNcfUsage(String customerId) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.customersNcfUsage,
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );
    
    return maps.isEmpty ? null : maps.first;
  }

  /// Actualiza el uso de NCF por cliente
  static Future<void> updateCustomerNcfUsage(String customerId, String lastNcfType) async {
    final db = await AppDb.database;
    
    final existing = await getCustomerNcfUsage(customerId);
    
    if (existing == null) {
      await db.insert(DbTables.customersNcfUsage, {
        'customer_id': customerId,
        'last_ncf_type': lastNcfType,
        'last_used_at': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await db.update(
        DbTables.customersNcfUsage,
        {
          'last_ncf_type': lastNcfType,
          'last_used_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'customer_id = ?',
        whereArgs: [customerId],
      );
    }
  }
}
