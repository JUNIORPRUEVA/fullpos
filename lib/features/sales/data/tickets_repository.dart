import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'ticket_model.dart';

class TicketsRepository {
  /// Guarda un ticket completo (carrito) con sus items
  Future<int> saveTicket({
    required String ticketName,
    int? userId,
    int? clientId,
    required double subtotal,
    required bool itbisEnabled,
    required double itbisRate,
    required double itbisAmount,
    required double discountTotal,
    required double total,
    required List<PosTicketItemModel> items,
  }) async {
    final database = await AppDb.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    return await database.transaction((txn) async {
      // Insertar ticket
      final ticketId = await txn.insert(DbTables.posTickets, {
        'ticket_name': ticketName,
        'user_id': userId,
        'client_id': clientId,
        'subtotal': subtotal,
        'itbis_enabled': itbisEnabled ? 1 : 0,
        'itbis_rate': itbisRate,
        'itbis_amount': itbisAmount,
        'discount_total': discountTotal,
        'total': total,
        'created_at_ms': nowMs,
        'updated_at_ms': nowMs,
      });

      // Insertar items
      for (var item in items) {
        await txn.insert(DbTables.posTicketItems, {
          'ticket_id': ticketId,
          'product_id': item.productId,
          'product_code_snapshot': item.productCodeSnapshot,
          'product_name_snapshot': item.productNameSnapshot,
          'description': item.description,
          'qty': item.qty,
          'price': item.price,
          'cost': item.cost,
          'discount_line': item.discountLine,
          'total_line': item.totalLine,
        });
      }

      return ticketId;
    });
  }

  /// Actualiza el nombre de un ticket
  Future<void> updateTicketName(int ticketId, String newName) async {
    final database = await AppDb.database;
    await database.update(
      DbTables.posTickets,
      {
        'ticket_name': newName,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [ticketId],
    );
  }

  /// Actualiza ticket completo (útil cuando el carrito cambia)
  Future<void> updateTicket({
    required int ticketId,
    String? ticketName,
    int? clientId,
    double? subtotal,
    required bool itbisEnabled,
    required double itbisRate,
    double? itbisAmount,
    required double discountTotal,
    double? total,
    required List<PosTicketItemModel> items,
  }) async {
    final database = await AppDb.database;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await database.transaction((txn) async {
      // Actualizar header
      final Map<String, dynamic> updates = {
        'itbis_enabled': itbisEnabled ? 1 : 0,
        'itbis_rate': itbisRate,
        'discount_total': discountTotal,
        'updated_at_ms': nowMs,
      };
      if (ticketName != null) updates['ticket_name'] = ticketName;
      if (clientId != null) updates['client_id'] = clientId;
      if (subtotal != null) updates['subtotal'] = subtotal;
      if (itbisAmount != null) updates['itbis_amount'] = itbisAmount;
      if (total != null) updates['total'] = total;

      await txn.update(
        DbTables.posTickets,
        updates,
        where: 'id = ?',
        whereArgs: [ticketId],
      );

      // Eliminar items viejos
      await txn.delete(
        DbTables.posTicketItems,
        where: 'ticket_id = ?',
        whereArgs: [ticketId],
      );

      // Insertar items nuevos
      for (var item in items) {
        await txn.insert(DbTables.posTicketItems, {
          'ticket_id': ticketId,
          'product_id': item.productId,
          'product_code_snapshot': item.productCodeSnapshot,
          'product_name_snapshot': item.productNameSnapshot,
          'description': item.description,
          'qty': item.qty,
          'price': item.price,
          'cost': item.cost,
          'discount_line': item.discountLine,
          'total_line': item.totalLine,
        });
      }
    });
  }

  /// Obtiene un ticket por ID con sus items
  Future<PosTicketModel?> getTicketById(int ticketId) async {
    final database = await AppDb.database;
    final results = await database.query(
      DbTables.posTickets,
      where: 'id = ?',
      whereArgs: [ticketId],
    );

    if (results.isEmpty) return null;
    return PosTicketModel.fromMap(results.first);
  }

  /// Obtiene los items de un ticket
  Future<List<PosTicketItemModel>> getTicketItems(int ticketId) async {
    final database = await AppDb.database;
    final results = await database.query(
      DbTables.posTicketItems,
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
    );
    return results.map((map) => PosTicketItemModel.fromMap(map)).toList();
  }

  /// Obtiene los items de multiples tickets en una sola consulta (mejor rendimiento).
  Future<Map<int, List<PosTicketItemModel>>> getTicketItemsByTicketIds(
    List<int> ticketIds,
  ) async {
    if (ticketIds.isEmpty) return {};
    final database = await AppDb.database;
    final placeholders = List.filled(ticketIds.length, '?').join(',');
    final results = await database.query(
      DbTables.posTicketItems,
      where: 'ticket_id IN ($placeholders)',
      whereArgs: ticketIds,
      orderBy: 'ticket_id ASC, id ASC',
    );

    final grouped = <int, List<PosTicketItemModel>>{};
    for (final row in results) {
      final ticketId = row['ticket_id'] as int? ?? 0;
      grouped.putIfAbsent(ticketId, () => <PosTicketItemModel>[]).add(
        PosTicketItemModel.fromMap(row),
      );
    }
    return grouped;
  }

  /// Lista todos los tickets guardados
  Future<List<PosTicketModel>> listTickets() async {
    final database = await AppDb.database;
    final results = await database.query(
      DbTables.posTickets,
      orderBy: 'updated_at_ms DESC',
    );
    return results.map((map) => PosTicketModel.fromMap(map)).toList();
  }

  /// Elimina un ticket (CASCADE eliminará items)
  Future<void> deleteTicket(int ticketId) async {
    final database = await AppDb.database;
    await database.delete(
      DbTables.posTickets,
      where: 'id = ?',
      whereArgs: [ticketId],
    );
  }
}
