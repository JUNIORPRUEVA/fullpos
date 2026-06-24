import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/tables.dart';
import '../logging/app_logger.dart';
import 'cash_close_activity_tracker.dart';
import 'import_export_activity_tracker.dart';
import 'print_activity_tracker.dart';
import 'update_block_reason.dart';

class AppUpdateSafetyResult {
  const AppUpdateSafetyResult({
    required this.safe,
    this.blockReason,
    this.blockReasons = const [],
    this.warning,
  });

  final bool safe;

  /// Razón de bloqueo como texto simple (legacy).
  final String? blockReason;

  /// Razones de bloqueo estructuradas con código, título, mensaje y acción.
  final List<UpdateBlockReason> blockReasons;

  final String? warning;

  /// Retorna la razón de mayor prioridad, o null si no hay bloqueos.
  UpdateBlockReason? get highestPriorityReason {
    if (blockReasons.isEmpty) return null;
    return blockReasons.reduce(
      (a, b) => a.priority <= b.priority ? a : b,
    );
  }
}

class AppUpdateSafetyValidator {
  const AppUpdateSafetyValidator();

  static const pendingWorkMessage =
      'No podemos instalar la actualización ahora porque hay una venta o proceso pendiente. Finaliza lo que estás haciendo y vuelve a intentarlo.';

  static const printingActiveMessage =
      'No podemos instalar la actualización ahora porque hay una impresión en proceso. Espera que termine la impresión y vuelve a intentarlo.';

  static const importExportActiveMessage =
      'No podemos instalar la actualización ahora porque hay una importación o exportación de datos en proceso. Espera que termine y vuelve a intentarlo.';

  static const cashClosingActiveMessage =
      'No podemos instalar la actualización ahora porque el cierre de caja está en proceso. Espera que termine y vuelve a intentarlo.';

  Future<AppUpdateSafetyResult> validate() async {
    final db = await AppDb.database;
    final reasons = <UpdateBlockReason>[];

    // Check active print jobs
    if (PrintActivityTracker.instance.isPrinting) {
      await AppLogger.instance.logWarn(
        'Active print job detected; update blocked',
        module: 'app_update',
      );
      reasons.add(UpdateBlockReason.activePrinting);
    }

    // Check active import/export operations
    if (ImportExportActivityTracker.instance.isActive) {
      await AppLogger.instance.logWarn(
        'Active import/export operation detected; update blocked',
        module: 'app_update',
      );
      reasons.add(UpdateBlockReason.importExportRunning);
    }

    // Check active cash shift closing
    if (CashCloseActivityTracker.instance.isClosing) {
      await AppLogger.instance.logWarn(
        'Active cash shift closing detected; update blocked',
        module: 'app_update',
      );
      reasons.add(UpdateBlockReason.cashClosingInProgress);
    }

    final openTickets = await _countRows(db, DbTables.posTickets);
    final tempCarts = await _countRows(db, DbTables.tempCarts);
    await AppLogger.instance.logInfo(
      'Active sale check openTickets=$openTickets tempCarts=$tempCarts',
      module: 'app_update',
    );
    if (openTickets > 0 || tempCarts > 0) {
      await AppLogger.instance.logWarn(
        'Active sale detected; update blocked',
        module: 'app_update',
      );
      reasons.add(UpdateBlockReason.activeSale);
    }

    final cloudSyncing = await _countRows(
      db,
      DbTables.syncOutbox,
      where: 'LOWER(status) = ?',
      whereArgs: const ['syncing'],
    );
    final productSyncing = await _countRows(
      db,
      DbTables.productSyncOutbox,
      where: 'LOWER(status) = ?',
      whereArgs: const ['syncing'],
    );
    await AppLogger.instance.logInfo(
      'Sync active check cloudSyncing=$cloudSyncing productSyncing=$productSyncing',
      module: 'app_update',
    );
    if (cloudSyncing > 0 || productSyncing > 0) {
      reasons.add(UpdateBlockReason.activeSync);
    }

    final openCashShifts = await _countRows(
      db,
      DbTables.cashSessions,
      where: 'UPPER(status) = ? AND closed_at_ms IS NULL',
      whereArgs: const ['OPEN'],
    );
    await AppLogger.instance.logInfo(
      'Safe update validation passed openCashShifts=$openCashShifts',
      module: 'app_update',
    );

    if (reasons.isNotEmpty) {
      return AppUpdateSafetyResult(
        safe: false,
        blockReason: reasons.first.message,
        blockReasons: reasons,
      );
    }

    return AppUpdateSafetyResult(
      safe: true,
      warning: openCashShifts > 0
          ? 'Hay una caja abierta. Es recomendable cerrarla antes de actualizar.'
          : null,
    );
  }


  Future<int> _countRows(
    Database db,
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (!await _tableExists(db, table)) return 0;
    final rows = await db.query(
      table,
      columns: const ['COUNT(*) AS total'],
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', table],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
