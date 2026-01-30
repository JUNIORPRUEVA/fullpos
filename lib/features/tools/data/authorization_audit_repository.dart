import 'dart:convert';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';

class AuthorizationAuditEntry {
  final int id;
  final int companyId;
  final String actionCode;
  final String? resourceType;
  final String? resourceId;
  final int? requestedByUserId;
  final int? approvedByUserId;
  final String? requestedByName;
  final String? approvedByName;
  final String? requestedByUsername;
  final String? approvedByUsername;
  final String? method;
  final String result;
  final String? terminalId;
  final Map<String, dynamic>? meta;
  final int createdAtMs;

  AuthorizationAuditEntry({
    required this.id,
    required this.companyId,
    required this.actionCode,
    required this.resourceType,
    required this.resourceId,
    required this.requestedByUserId,
    required this.approvedByUserId,
    required this.requestedByName,
    required this.approvedByName,
    required this.requestedByUsername,
    required this.approvedByUsername,
    required this.method,
    required this.result,
    required this.terminalId,
    required this.meta,
    required this.createdAtMs,
  });

  String get requestedLabel {
    final name = (requestedByName ?? requestedByUsername ?? '').trim();
    return name.isEmpty ? 'N/A' : name;
  }

  String get approvedLabel {
    final name = (approvedByName ?? approvedByUsername ?? '').trim();
    return name.isEmpty ? 'N/A' : name;
  }
}

class AuthorizationAuditRepository {
  AuthorizationAuditRepository._();

  static Future<List<AuthorizationAuditEntry>> listAudits({
    required int companyId,
    int limit = 200,
  }) async {
    final db = await AppDb.database;
    final rows = await db.rawQuery('''
      SELECT a.*,
             req.display_name AS requested_name,
             req.username AS requested_username,
             app.display_name AS approved_name,
             app.username AS approved_username
      FROM ${DbTables.auditLog} a
      LEFT JOIN ${DbTables.users} req
        ON req.id = a.requested_by_user_id
      LEFT JOIN ${DbTables.users} app
        ON app.id = a.approved_by_user_id
      WHERE a.company_id = ?
      ORDER BY a.created_at_ms DESC
      LIMIT ?
    ''', [companyId, limit]);

    return rows.map((row) {
      final metaRaw = row['meta'] as String?;
      Map<String, dynamic>? meta;
      if (metaRaw != null && metaRaw.trim().isNotEmpty) {
        try {
          meta = jsonDecode(metaRaw) as Map<String, dynamic>;
        } catch (_) {
          meta = null;
        }
      }

      return AuthorizationAuditEntry(
        id: row['id'] as int,
        companyId: row['company_id'] as int,
        actionCode: row['action_code'] as String,
        resourceType: row['resource_type'] as String?,
        resourceId: row['resource_id'] as String?,
        requestedByUserId: row['requested_by_user_id'] as int?,
        approvedByUserId: row['approved_by_user_id'] as int?,
        requestedByName: row['requested_name'] as String?,
        approvedByName: row['approved_name'] as String?,
        requestedByUsername: row['requested_username'] as String?,
        approvedByUsername: row['approved_username'] as String?,
        method: row['method'] as String?,
        result: row['result'] as String? ?? 'unknown',
        terminalId: row['terminal_id'] as String?,
        meta: meta,
        createdAtMs: row['created_at_ms'] as int,
      );
    }).toList();
  }
}
