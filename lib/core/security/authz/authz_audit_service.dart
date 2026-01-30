import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../db/app_db.dart';
import '../../db/tables.dart';

/// Auditoría para intentos de acceso/acciones y resultados de override.
///
/// Usa la misma tabla `audit_log` ya existente.
class AuthzAuditService {
  AuthzAuditService._();

  static Future<void> log({
    required int companyId,
    required String permissionCode,
    required String result,
    required String terminalId,
    int? requestedByUserId,
    int? approvedByUserId,
    String? method,
    String? resourceType,
    String? resourceId,
    Map<String, dynamic>? meta,
    DatabaseExecutor? db,
  }) async {
    final executor = db ?? await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await executor.insert(
      DbTables.auditLog,
      {
        'company_id': companyId,
        'action_code': permissionCode,
        'resource_type': resourceType,
        'resource_id': resourceId,
        'requested_by_user_id': requestedByUserId,
        'approved_by_user_id': approvedByUserId,
        'method': method,
        'result': result,
        'terminal_id': terminalId,
        'meta': meta == null ? null : jsonEncode(meta),
        'created_at_ms': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

