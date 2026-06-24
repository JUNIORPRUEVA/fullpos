import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/tables.dart';
import 'temporary_authorization_service.dart';

enum OverrideMethod { adminCode }

class AuthorizationResult {
  final bool success;
  final String message;
  final OverrideMethod method;
  final int? approvedByUserId;

  AuthorizationResult({
    required this.success,
    required this.message,
    required this.method,
    this.approvedByUserId,
  });
}

class AuthorizationService {
  AuthorizationService._();

  static Future<AuthorizationResult> authorizeWithAdminCode({
    required String code,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int requestedByUserId,
    required String terminalId,
  }) async {
    final normalizedCode = code.trim();
    final db = await AppDb.database;

    if (normalizedCode.isEmpty) {
      await _logAudit(
        db: db,
        companyId: companyId,
        actionCode: actionCode,
        resourceType: resourceType,
        resourceId: resourceId,
        requestedBy: requestedByUserId,
        approvedBy: null,
        method: OverrideMethod.adminCode,
        result: 'invalid',
        terminalId: terminalId,
        meta: {'reason': 'empty_code'},
      );
      return AuthorizationResult(
        success: false,
        message: 'Ingresa el código de administración',
        method: OverrideMethod.adminCode,
      );
    }

    final adminId = await _findAdminByCode(
      db: db,
      companyId: companyId,
      code: normalizedCode,
    );

    if (adminId == null) {
      await _logAudit(
        db: db,
        companyId: companyId,
        actionCode: actionCode,
        resourceType: resourceType,
        resourceId: resourceId,
        requestedBy: requestedByUserId,
        approvedBy: null,
        method: OverrideMethod.adminCode,
        result: 'invalid',
        terminalId: terminalId,
        meta: {'reason': 'admin_code_not_found'},
      );
      return AuthorizationResult(
        success: false,
        message: 'Código de administración inválido',
        method: OverrideMethod.adminCode,
      );
    }

    await _logAudit(
      db: db,
      companyId: companyId,
      actionCode: actionCode,
      resourceType: resourceType,
      resourceId: resourceId,
      requestedBy: requestedByUserId,
      approvedBy: adminId,
      method: OverrideMethod.adminCode,
      result: 'approved',
      terminalId: terminalId,
    );

    TemporaryAuthorizationService.authorize(
      scope: actionCode,
      approvedByUserId: adminId.toString(),
    );

    return AuthorizationResult(
      success: true,
      message: 'Autorización aprobada',
      method: OverrideMethod.adminCode,
      approvedByUserId: adminId,
    );
  }

  static Future<int?> _findAdminByCode({
    required DatabaseExecutor db,
    required int companyId,
    required String code,
  }) async {
    final rows = await db.query(
      DbTables.users,
      columns: ['id'],
      where:
          'company_id = ? AND pin = ? AND LOWER(role) IN (?, ?) AND is_active = 1 AND deleted_at_ms IS NULL',
      whereArgs: [companyId, code, 'admin', 'supervisor'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  static String _methodToString(OverrideMethod method) {
    switch (method) {
      case OverrideMethod.adminCode:
        return 'admin_code';
    }
  }

  static Future<void> _logAudit({
    required DatabaseExecutor db,
    required int companyId,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int? requestedBy,
    required int? approvedBy,
    required OverrideMethod method,
    required String result,
    required String terminalId,
    Map<String, dynamic>? meta,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(DbTables.auditLog, {
      'company_id': companyId,
      'action_code': actionCode,
      'resource_type': resourceType,
      'resource_id': resourceId,
      'requested_by_user_id': requestedBy,
      'approved_by_user_id': approvedBy,
      'method': _methodToString(method),
      'result': result,
      'terminal_id': terminalId,
      'meta': meta != null ? jsonEncode(meta) : null,
      'created_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
