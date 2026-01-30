import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'quote_model.dart';
import 'package:sqflite/sqflite.dart';

class QuotesRepository {
  Future<Set<String>> _getTableColumns(DatabaseExecutor executor, String table) async {
    final info = await executor.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name']).whereType<String>().toSet();
  }

  Future<void> _insertQuoteItem(
    DatabaseExecutor executor, {
    required int quoteId,
    required QuoteItemModel item,
    required Set<String> columns,
  }) async {
    final map = <String, Object?>{
      'quote_id': quoteId,
      'product_id': item.productId,
      'product_code_snapshot': item.productCode,
      'product_name_snapshot': item.productName,
      'description': item.description,
      'qty': item.qty,
      // Compatibilidad: algunos esquemas antiguos usan unit_price NOT NULL.
      'unit_price': item.unitPrice,
      'price': item.price,
      'cost': item.cost,
      'discount_line': item.discountLine,
      'total_line': item.totalLine,
      // Compatibilidad adicional por si existieran nombres antiguos.
      'product_code': item.productCode,
      'product_name': item.productName,
    };

    map.removeWhere((key, _) => !columns.contains(key));
    await executor.insert(DbTables.quoteItems, map);
  }

  /// Guarda una cotización completa con sus items (en transacción)
  Future<int> saveQuote({
    required int clientId,
    int? userId,
    String? ticketName,
    required double subtotal,
    required bool itbisEnabled,
    required double itbisRate,
    required double itbisAmount,
    required double discountTotal,
    required double total,
    String? notes,
    required List<QuoteItemModel> items,
  }) async {
    final database = await AppDb.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    return await database.transaction((txn) async {
      // Insertar quote
      final quoteId = await txn.insert(DbTables.quotes, {
        'client_id': clientId,
        'user_id': userId,
        'ticket_name': ticketName,
        'subtotal': subtotal,
        'itbis_enabled': itbisEnabled ? 1 : 0,
        'itbis_rate': itbisRate,
        'itbis_amount': itbisAmount,
        'discount_total': discountTotal,
        'total': total,
        'status': 'OPEN',
        'notes': notes,
        'created_at_ms': nowMs,
        'updated_at_ms': nowMs,
      });

      // Insertar items
      final quoteItemColumns = await _getTableColumns(txn, DbTables.quoteItems);
      for (var item in items) {
        await _insertQuoteItem(
          txn,
          quoteId: quoteId,
          item: item,
          columns: quoteItemColumns,
        );
      }

      return quoteId;
    });
  }

  /// Lista todas las cotizaciones con datos del cliente
  Future<List<QuoteDetailDto>> listQuotes({
    String? status,
    int? clientId,
    String? orderBy = 'created_at_ms DESC',
  }) async {
    final database = await AppDb.database;

    String where = '1=1';
    List<dynamic> whereArgs = [];

    if (status != null) {
      where += ' AND q.status = ?';
      whereArgs.add(status);
    }
    if (clientId != null) {
      where += ' AND q.client_id = ?';
      whereArgs.add(clientId);
    }

    final results = await database.rawQuery('''
      SELECT 
        q.*,
        c.nombre AS client_name,
        c.telefono AS client_phone,
        c.rnc AS client_rnc
      FROM ${DbTables.quotes} q
      INNER JOIN ${DbTables.clients} c ON q.client_id = c.id
      WHERE $where
      ORDER BY ${orderBy ?? 'q.created_at_ms DESC'}
    ''', whereArgs);

    List<QuoteDetailDto> quotes = [];
    for (var row in results) {
      final quote = QuoteModel.fromMap(row);
      final items = await _getQuoteItems(quote.id!);

      quotes.add(
        QuoteDetailDto(
          quote: quote,
          clientName: row['client_name'] as String,
          clientPhone: row['client_phone'] as String?,
          clientRnc: row['client_rnc'] as String?,
          items: items,
        ),
      );
    }

    return quotes;
  }

  /// Obtiene los items de una cotización
  Future<List<QuoteItemModel>> _getQuoteItems(int quoteId) async {
    final database = await AppDb.database;
    final results = await database.query(
      DbTables.quoteItems,
      where: 'quote_id = ?',
      whereArgs: [quoteId],
    );
    return results.map((map) => QuoteItemModel.fromMap(map)).toList();
  }

  /// Obtiene una cotización por ID con detalles
  Future<QuoteDetailDto?> getQuoteById(int quoteId) async {
    final database = await AppDb.database;

    final results = await database.rawQuery(
      '''
      SELECT 
        q.*,
        c.nombre AS client_name,
        c.telefono AS client_phone,
        c.rnc AS client_rnc
      FROM ${DbTables.quotes} q
      INNER JOIN ${DbTables.clients} c ON q.client_id = c.id
      WHERE q.id = ?
    ''',
      [quoteId],
    );

    if (results.isEmpty) return null;

    final row = results.first;
    final quote = QuoteModel.fromMap(row);
    final items = await _getQuoteItems(quoteId);

    return QuoteDetailDto(
      quote: quote,
      clientName: row['client_name'] as String,
      clientPhone: row['client_phone'] as String?,
      clientRnc: row['client_rnc'] as String?,
      items: items,
    );
  }

  /// Actualiza el estado de una cotización
  Future<void> updateQuoteStatus(int quoteId, String status) async {
    final database = await AppDb.database;
    await database.update(
      DbTables.quotes,
      {
        'status': status,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [quoteId],
    );
  }

  /// Elimina una cotización (CASCADE borrará items automáticamente)
  Future<void> deleteQuote(int quoteId) async {
    final database = await AppDb.database;
    await database.delete(
      DbTables.quotes,
      where: 'id = ?',
      whereArgs: [quoteId],
    );
  }

  /// Duplica una cotización con todos sus items
  Future<int> duplicateQuote(int quoteId) async {
    final database = await AppDb.database;
    final original = await getQuoteById(quoteId);
    if (original == null) throw Exception('Cotización no encontrada');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return await database.transaction((txn) async {
      // Crear nueva cotización basada en la original
      final newQuoteId = await txn.insert(DbTables.quotes, {
        'client_id': original.quote.clientId,
        'user_id': original.quote.userId,
        'ticket_name': '${original.quote.ticketName ?? ''} (Copia)',
        'subtotal': original.quote.subtotal,
        'itbis_enabled': original.quote.itbisEnabled ? 1 : 0,
        'itbis_rate': original.quote.itbisRate,
        'itbis_amount': original.quote.itbisAmount,
        'discount_total': original.quote.discountTotal,
        'total': original.quote.total,
        'status': 'OPEN',
        'notes': original.quote.notes,
        'created_at_ms': nowMs,
        'updated_at_ms': nowMs,
      });

      // Copiar items
      final quoteItemColumns = await _getTableColumns(txn, DbTables.quoteItems);
      for (var item in original.items) {
        await _insertQuoteItem(
          txn,
          quoteId: newQuoteId,
          item: item,
          columns: quoteItemColumns,
        );
      }

      return newQuoteId;
    });
  }

  /// Actualiza una cotización existente
  Future<void> updateQuote({
    required int quoteId,
    int? clientId,
    String? ticketName,
    double? subtotal,
    bool? itbisEnabled,
    double? itbisRate,
    double? itbisAmount,
    double? discountTotal,
    double? total,
    String? notes,
    List<QuoteItemModel>? items,
  }) async {
    final database = await AppDb.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await database.transaction((txn) async {
      // Actualizar cotización
      await txn.update(
        DbTables.quotes,
        {
          if (clientId != null) 'client_id': clientId,
          if (ticketName != null) 'ticket_name': ticketName,
          if (subtotal != null) 'subtotal': subtotal,
          if (itbisEnabled != null) 'itbis_enabled': itbisEnabled ? 1 : 0,
          if (itbisRate != null) 'itbis_rate': itbisRate,
          if (itbisAmount != null) 'itbis_amount': itbisAmount,
          if (discountTotal != null) 'discount_total': discountTotal,
          if (total != null) 'total': total,
          if (notes != null) 'notes': notes,
          'updated_at_ms': nowMs,
        },
        where: 'id = ?',
        whereArgs: [quoteId],
      );

      // Si se proporcionan items, actualizar los items
      if (items != null) {
        // Eliminar items antiguos
        await txn.delete(
          DbTables.quoteItems,
          where: 'quote_id = ?',
          whereArgs: [quoteId],
        );

        // Insertar nuevos items
        final quoteItemColumns = await _getTableColumns(txn, DbTables.quoteItems);
        for (var item in items) {
          await _insertQuoteItem(
            txn,
            quoteId: quoteId,
            item: item,
            columns: quoteItemColumns,
          );
        }
      }
    });
  }
}
