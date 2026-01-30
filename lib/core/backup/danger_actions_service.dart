import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/sales/data/cash_repository.dart';
import '../../features/sales/data/temp_cart_repository.dart';
import '../../features/settings/data/users_repository.dart';
import '../db/app_db.dart';
import '../db/database_manager.dart';
import '../db/tables.dart';
import '../session/session_manager.dart';
import '../utils/id_utils.dart';
import 'backup_models.dart';
import 'backup_paths.dart';
import 'backup_repository.dart';
import 'cloud_backup_service.dart';

class DangerActionResult {
  DangerActionResult({
    required this.ok,
    required this.messageUser,
    this.messageDev,
  });

  final bool ok;
  final String messageUser;
  final String? messageDev;
}

class DangerActionsService {
  DangerActionsService._();

  static final DangerActionsService instance = DangerActionsService._();

  Future<DangerActionResult> resetLocal({
    required String confirmedPhrase,
    required String pin,
  }) async {
    final guard = await _checkGuards(
      confirmedPhrase: confirmedPhrase,
      pin: pin,
      expectedPhrase: 'RESETEAR EMPRESA',
    );
    if (guard != null) return guard;

    final companyId = (await SessionManager.companyId() ?? 1).toString();
    final userId = await SessionManager.userId() ?? 0;
    final logEntry = DangerActionLogEntry(
      id: IdUtils.uuidV4(),
      empresaId: companyId,
      usuarioId: userId,
      action: 'RESET_LOCAL',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      confirmedByPhrase: confirmedPhrase,
      result: 'IN_PROGRESS',
    );
    await BackupRepository.instance.insertDangerAction(logEntry);

    try {
      final db = await AppDb.database;
      await db.transaction((txn) async {
        for (final table in _resetTables) {
          await txn.delete(table);
        }
      });

      await BackupRepository.instance.insertDangerAction(
        DangerActionLogEntry(
          id: IdUtils.uuidV4(),
          empresaId: companyId,
          usuarioId: userId,
          action: 'RESET_LOCAL',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          confirmedByPhrase: confirmedPhrase,
          result: 'SUCCESS',
        ),
      );

      return DangerActionResult(
        ok: true,
        messageUser: 'Empresa reseteada correctamente.',
      );
    } catch (e) {
      await BackupRepository.instance.insertDangerAction(
        DangerActionLogEntry(
          id: IdUtils.uuidV4(),
          empresaId: companyId,
          usuarioId: userId,
          action: 'RESET_LOCAL',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          confirmedByPhrase: confirmedPhrase,
          result: 'FAILED',
          errorMessage: e.toString(),
        ),
      );
      return DangerActionResult(
        ok: false,
        messageUser: 'No se pudo resetear la empresa.',
        messageDev: e.toString(),
      );
    }
  }

  Future<DangerActionResult> deleteAllLocal({
    required String confirmedPhrase,
    required String pin,
  }) async {
    final guard = await _checkGuards(
      confirmedPhrase: confirmedPhrase,
      pin: pin,
      expectedPhrase: 'BORRAR TODO FULLPOS',
    );
    if (guard != null) return guard;

    final companyId = (await SessionManager.companyId() ?? 1).toString();
    final userId = await SessionManager.userId() ?? 0;

    // keep message simple
    try {
      await DatabaseManager.instance.close(reason: 'danger_delete_all');
      final dbPath = await BackupPaths.databaseFilePath();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final baseDir = await BackupPaths.backupsBaseDir();
      if (await baseDir.exists()) {
        await baseDir.delete(recursive: true);
      }

      await BackupRepository.instance.insertDangerAction(
        DangerActionLogEntry(
          id: IdUtils.uuidV4(),
          empresaId: companyId,
          usuarioId: userId,
          action: 'DELETE_ALL_LOCAL',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          confirmedByPhrase: confirmedPhrase,
          result: 'SUCCESS',
        ),
      );

      return DangerActionResult(
        ok: true,
        messageUser: 'Base local eliminada. Reinicia la app.',
      );
    } catch (e) {
      await BackupRepository.instance.insertDangerAction(
        DangerActionLogEntry(
          id: IdUtils.uuidV4(),
          empresaId: companyId,
          usuarioId: userId,
          action: 'DELETE_ALL_LOCAL',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          confirmedByPhrase: confirmedPhrase,
          result: 'FAILED',
          errorMessage: e.toString(),
        ),
      );
      return DangerActionResult(
        ok: false,
        messageUser: 'No se pudo borrar la base de datos local.',
        messageDev: e.toString(),
      );
    }
  }

  Future<DangerActionResult> resetCloud({
    required String confirmedPhrase,
    required String pin,
  }) async {
    final guard = await _checkGuards(
      confirmedPhrase: confirmedPhrase,
      pin: pin,
      expectedPhrase: 'RESETEAR EMPRESA',
    );
    if (guard != null) return guard;

    final ok = await CloudBackupService.instance.resetCompany(
      phrase: confirmedPhrase,
      adminPin: pin,
    );
    return DangerActionResult(
      ok: ok,
      messageUser: ok
          ? 'Empresa reseteada en la nube.'
          : 'No se pudo resetear la nube.',
    );
  }

  Future<DangerActionResult> deleteAllCloud({
    required String confirmedPhrase,
    required String pin,
  }) async {
    final guard = await _checkGuards(
      confirmedPhrase: confirmedPhrase,
      pin: pin,
      expectedPhrase: 'BORRAR TODO FULLPOS',
    );
    if (guard != null) return guard;

    final ok = await CloudBackupService.instance.deleteCompany(
      phrase: confirmedPhrase,
      adminPin: pin,
    );
    return DangerActionResult(
      ok: ok,
      messageUser: ok
          ? 'Datos de empresa borrados en la nube.'
          : 'No se pudo borrar la nube.',
    );
  }

  Future<DangerActionResult?> _checkGuards({
    required String confirmedPhrase,
    required String pin,
    required String expectedPhrase,
  }) async {
    if (confirmedPhrase.trim().toUpperCase() != expectedPhrase) {
      return DangerActionResult(
        ok: false,
        messageUser: 'La frase de confirmaciÃ³n no coincide.',
      );
    }

    if (!await SessionManager.isAdmin()) {
      return DangerActionResult(
        ok: false,
        messageUser: 'Solo un administrador puede ejecutar esta acciÃ³n.',
      );
    }

    final username = await SessionManager.username();
    if (username == null) {
      return DangerActionResult(ok: false, messageUser: 'SesiÃ³n invÃ¡lida.');
    }

    final user = await UsersRepository.verifyPin(username, pin);
    if (user == null) {
      return DangerActionResult(ok: false, messageUser: 'PIN incorrecto.');
    }

    final carts = await TempCartRepository().getAllCarts();
    if (carts.isNotEmpty) {
      return DangerActionResult(
        ok: false,
        messageUser:
            'Hay una venta en proceso. Cierra la transacciÃ³n antes de continuar.',
      );
    }

    final openSessions = await CashRepository.getOpenSessions();
    if (openSessions.isNotEmpty) {
      return DangerActionResult(
        ok: false,
        messageUser:
            'Hay una caja abierta. Cierra la sesiÃ³n antes de continuar.',
      );
    }

    return null;
  }

  static const List<String> _resetTables = [
    DbTables.sales,
    DbTables.saleItems,
    DbTables.returns,
    DbTables.returnItems,
    DbTables.posTickets,
    DbTables.posTicketItems,
    DbTables.quotes,
    DbTables.quoteItems,
    DbTables.cashMovements,
    DbTables.cashSessions,
    DbTables.stockMovements,
    DbTables.tempCartItems,
    DbTables.tempCarts,
    DbTables.purchaseOrderItems,
    DbTables.purchaseOrders,
    DbTables.creditPayments,
  ];
}
