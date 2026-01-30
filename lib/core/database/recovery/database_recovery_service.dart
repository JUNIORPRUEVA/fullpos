import '../../db/app_db.dart';
import '../../db/tables.dart';
import '../../errors/error_mapper.dart';
import '../../logging/app_logger.dart';

class DatabaseRecoveryService {
  DatabaseRecoveryService._();

  static const Duration defaultAbandonedTicketAge = Duration(minutes: 10);

  static Future<void> run({Duration maxAge = defaultAbandonedTicketAge}) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final thresholdMs = now - maxAge.inMilliseconds;

    try {
      // pos_tickets actúa como "draft" de carritos/tickets pendientes.
      // Si la app se cerró inesperadamente y quedan registros muy viejos,
      // los limpiamos para no dejar basura/inconsistencias.
      final deleted = await db.delete(
        DbTables.posTickets,
        where: 'updated_at_ms < ?',
        whereArgs: [thresholdMs],
      );

      if (deleted > 0) {
        await AppLogger.instance.logInfo(
          'Recovery: deleted $deleted abandoned POS tickets older than ${maxAge.inMinutes}m',
          module: 'recovery',
        );
      }
    } catch (e, st) {
      final ex = ErrorMapper.map(e, st, 'recovery');
      await AppLogger.instance.logError(ex, module: 'recovery');
    }
  }
}
