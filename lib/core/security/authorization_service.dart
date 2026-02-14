import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../network/api_client.dart';
import '../db/app_db.dart';
import '../db/tables.dart';

enum OverrideMethod { offlinePin, offlineBarcode, remote }

class GeneratedOverrideToken {
  final String token;
  final DateTime expiresAt;
  final OverrideMethod method;
  final String nonce;

  GeneratedOverrideToken({
    required this.token,
    required this.expiresAt,
    required this.method,
    required this.nonce,
  });
}

class AuthorizationResult {
  final bool success;
  final String message;
  final OverrideMethod method;

  AuthorizationResult({
    required this.success,
    required this.message,
    required this.method,
  });
}

class RemoteOverrideRequest {
  final int requestId;
  final String status;

  RemoteOverrideRequest({required this.requestId, required this.status});
}

class AuthorizationService {
  AuthorizationService._();

  static const Duration defaultTtl = Duration(seconds: 120);
  static const Duration defaultRemoteTimeout = Duration(seconds: 8);

  static Future<GeneratedOverrideToken> generateOfflinePinToken({
    required String pin,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int requestedByUserId,
    required String terminalId,
    Duration ttl = defaultTtl,
  }) async {
    final db = await AppDb.database;
    final adminId = await _findAdminByPin(
      db: db,
      companyId: companyId,
      pin: pin,
    );
    if (adminId == null) {
      throw Exception('PIN de administrador invalido');
    }
    final now = DateTime.now();
    final expiresAt = now.add(ttl);
    final nonce = _randomToken(10);
    final payload =
        '$companyId|$actionCode|$resourceType|${resourceId ?? ''}|$requestedByUserId|$terminalId|$nonce|${expiresAt.millisecondsSinceEpoch}';
    final hmac = Hmac(sha256, utf8.encode(pin));
    final digest = hmac.convert(utf8.encode(payload));
    final tokenValue = _shortCodeFromDigest(digest);
    final tokenHash = _hashToken(tokenValue);

    await db.insert(DbTables.overrideTokens, {
      'company_id': companyId,
      'action_code': actionCode,
      'resource_type': resourceType,
      'resource_id': resourceId,
      'token_hash': tokenHash,
      'payload_signature': digest.toString(),
      'method': _methodToString(OverrideMethod.offlinePin),
      'nonce': nonce,
      'requested_by_user_id': requestedByUserId,
      'approved_by_user_id': adminId,
      'terminal_id': terminalId,
      'expires_at_ms': expiresAt.millisecondsSinceEpoch,
      'created_at_ms': now.millisecondsSinceEpoch,
      'result': 'issued',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _logAudit(
      db: db,
      companyId: companyId,
      actionCode: actionCode,
      resourceType: resourceType,
      resourceId: resourceId,
      requestedBy: requestedByUserId,
      approvedBy: adminId,
      method: OverrideMethod.offlinePin,
      result: 'issued',
      terminalId: terminalId,
      meta: {'nonce': nonce},
    );

    return GeneratedOverrideToken(
      token: tokenValue,
      expiresAt: expiresAt,
      method: OverrideMethod.offlinePin,
      nonce: nonce,
    );
  }

  static Future<GeneratedOverrideToken> generateLocalBarcodeToken({
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int requestedByUserId,
    required String terminalId,
    Duration ttl = defaultTtl,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now();
    final expiresAt = now.add(ttl);
    final nonce = _randomToken(12);
    final tokenValue = _randomToken(12);
    final tokenHash = _hashToken(tokenValue);

    await db.insert(DbTables.overrideTokens, {
      'company_id': companyId,
      'action_code': actionCode,
      'resource_type': resourceType,
      'resource_id': resourceId,
      'token_hash': tokenHash,
      'payload_signature': sha256.convert(utf8.encode(nonce)).toString(),
      'method': _methodToString(OverrideMethod.offlineBarcode),
      'nonce': nonce,
      'requested_by_user_id': requestedByUserId,
      'approved_by_user_id': requestedByUserId,
      'terminal_id': terminalId,
      'expires_at_ms': expiresAt.millisecondsSinceEpoch,
      'created_at_ms': now.millisecondsSinceEpoch,
      'result': 'issued',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _logAudit(
      db: db,
      companyId: companyId,
      actionCode: actionCode,
      resourceType: resourceType,
      resourceId: resourceId,
      requestedBy: requestedByUserId,
      approvedBy: requestedByUserId,
      method: OverrideMethod.offlineBarcode,
      result: 'issued',
      terminalId: terminalId,
      meta: {'nonce': nonce},
    );

    return GeneratedOverrideToken(
      token: tokenValue,
      expiresAt: expiresAt,
      method: OverrideMethod.offlineBarcode,
      nonce: nonce,
    );
  }

  static Future<AuthorizationResult> validateAndConsumeToken({
    required String token,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int usedByUserId,
    required String terminalId,
    bool allowRemote = false,
    String? remoteBaseUrl,
    String? remoteApiKey,
    int? remoteRequestId,
  }) async {
    final db = await AppDb.database;
    final tokenHash = _hashToken(token);
    final now = DateTime.now().millisecondsSinceEpoch;

    final localResult = await db.transaction((txn) async {
      final rows = await txn.query(
        DbTables.overrideTokens,
        where:
            'token_hash = ? AND company_id = ? AND action_code = ? AND used_at_ms IS NULL',
        whereArgs: [tokenHash, companyId, actionCode],
        limit: 1,
      );

      if (rows.isEmpty) {
        await _logAudit(
          db: txn,
          companyId: companyId,
          actionCode: actionCode,
          resourceType: resourceType,
          resourceId: resourceId,
          requestedBy: usedByUserId,
          approvedBy: null,
          method: OverrideMethod.offlineBarcode,
          result: 'invalid',
          terminalId: terminalId,
          meta: {'reason': 'not_found'},
        );
        return AuthorizationResult(
          success: false,
          message: 'Token invalido',
          method: OverrideMethod.offlineBarcode,
        );
      }

      final row = rows.first;
      final method = _methodFromString(row['method'] as String?);
      final expiresAtMs = row['expires_at_ms'] as int?;
      final dbResourceType = row['resource_type'] as String?;
      final dbResourceId = row['resource_id'] as String?;

      if (expiresAtMs != null && expiresAtMs < now) {
        await _markResult(txn, row['id'] as int, usedByUserId, 'expired', now);
        await _logAudit(
          db: txn,
          companyId: companyId,
          actionCode: actionCode,
          resourceType: resourceType,
          resourceId: resourceId,
          requestedBy: row['requested_by_user_id'] as int?,
          approvedBy: usedByUserId,
          method: method,
          result: 'expired',
          terminalId: terminalId,
        );
        return AuthorizationResult(
          success: false,
          message: 'Token vencido',
          method: method,
        );
      }

      if (dbResourceType != null &&
          dbResourceType.isNotEmpty &&
          dbResourceType != resourceType) {
        await _logAudit(
          db: txn,
          companyId: companyId,
          actionCode: actionCode,
          resourceType: resourceType,
          resourceId: resourceId,
          requestedBy: row['requested_by_user_id'] as int?,
          approvedBy: usedByUserId,
          method: method,
          result: 'resource_mismatch',
          terminalId: terminalId,
        );
        return AuthorizationResult(
          success: false,
          message: 'Token no corresponde al recurso',
          method: method,
        );
      }
      if (dbResourceId != null &&
          dbResourceId.isNotEmpty &&
          resourceId != null &&
          dbResourceId != resourceId) {
        await _logAudit(
          db: txn,
          companyId: companyId,
          actionCode: actionCode,
          resourceType: resourceType,
          resourceId: resourceId,
          requestedBy: row['requested_by_user_id'] as int?,
          approvedBy: usedByUserId,
          method: method,
          result: 'resource_mismatch',
          terminalId: terminalId,
        );
        return AuthorizationResult(
          success: false,
          message: 'Token no corresponde a este item',
          method: method,
        );
      }

      await txn.update(
        DbTables.overrideTokens,
        {
          'used_at_ms': now,
          'used_by_user_id': usedByUserId,
          'result': 'approved',
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );

      await _logAudit(
        db: txn,
        companyId: companyId,
        actionCode: actionCode,
        resourceType: resourceType,
        resourceId: resourceId,
        requestedBy: row['requested_by_user_id'] as int?,
        approvedBy: usedByUserId,
        method: method,
        result: 'approved',
        terminalId: terminalId,
      );

      return AuthorizationResult(
        success: true,
        message: 'Autorizacion aprobada',
        method: method,
      );
    });

    if (localResult.success) return localResult;

    if (!allowRemote || remoteBaseUrl == null || remoteBaseUrl.trim().isEmpty) {
      return localResult;
    }

    final remoteResult = await _verifyRemoteToken(
      baseUrl: remoteBaseUrl,
      apiKey: remoteApiKey,
      token: token,
      actionCode: actionCode,
      resourceType: resourceType,
      resourceId: resourceId,
      companyId: companyId,
      usedByUserId: usedByUserId,
      terminalId: terminalId,
    );

    if (!remoteResult.success) {
      return remoteResult;
    }

    await _storeRemoteApproval(
      db: db,
      token: token,
      actionCode: actionCode,
      resourceType: resourceType,
      resourceId: resourceId,
      companyId: companyId,
      usedByUserId: usedByUserId,
      terminalId: terminalId,
      requestId: remoteRequestId,
    );

    return remoteResult;
  }

  static Future<RemoteOverrideRequest> createRemoteOverrideRequest({
    required String baseUrl,
    String? apiKey,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int requestedByUserId,
    required String terminalId,
    Map<String, dynamic>? meta,
  }) async {
    final payload = {
      'companyId': companyId,
      'actionCode': actionCode,
      'resourceType': resourceType,
      'resourceId': resourceId,
      'requestedById': requestedByUserId,
      'terminalId': terminalId,
      if (meta != null) 'meta': meta,
    };

    final res = await _postJson(
      baseUrl: baseUrl,
      path: '/api/override/request',
      apiKey: apiKey,
      payload: payload,
    );

    final requestId = res['requestId'] as int?;
    final status = (res['status'] ?? 'pending').toString();
    if (requestId == null) {
      throw Exception('No se pudo crear la solicitud remota.');
    }

    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(DbTables.overrideRequests, {
      'id': requestId,
      'company_id': companyId,
      'action_code': actionCode,
      'resource_type': resourceType,
      'resource_id': resourceId,
      'requested_by_user_id': requestedByUserId,
      'status': status,
      'terminal_id': terminalId,
      'created_at_ms': now,
      'meta': meta != null ? jsonEncode(meta) : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _logAudit(
      db: db,
      companyId: companyId,
      actionCode: actionCode,
      resourceType: resourceType,
      resourceId: resourceId,
      requestedBy: requestedByUserId,
      approvedBy: null,
      method: OverrideMethod.remote,
      result: 'requested',
      terminalId: terminalId,
      meta: meta,
    );

    return RemoteOverrideRequest(requestId: requestId, status: status);
  }

  static String _hashToken(String token) {
    final bytes = utf8.encode(token);
    return sha256.convert(bytes).toString();
  }

  static Future<int?> _findAdminByPin({
    required DatabaseExecutor db,
    required int companyId,
    required String pin,
  }) async {
    final rows = await db.query(
      DbTables.users,
      columns: ['id'],
      where:
          'company_id = ? AND pin = ? AND role = ? AND is_active = 1 AND deleted_at_ms IS NULL',
      whereArgs: [companyId, pin, 'admin'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  static String _randomToken(int length) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[rand.nextInt(alphabet.length)],
    ).join();
  }

  static String _shortCodeFromDigest(Digest digest) {
    final chars = digest.bytes.take(6).map((b) => (b % 10).toString()).join();
    return chars.padLeft(6, '0');
  }

  static String _methodToString(OverrideMethod method) {
    switch (method) {
      case OverrideMethod.offlinePin:
        return 'offline_pin';
      case OverrideMethod.offlineBarcode:
        return 'offline_barcode';
      case OverrideMethod.remote:
        return 'remote';
    }
  }

  static OverrideMethod _methodFromString(String? method) {
    switch (method) {
      case 'offline_pin':
        return OverrideMethod.offlinePin;
      case 'remote':
        return OverrideMethod.remote;
      default:
        return OverrideMethod.offlineBarcode;
    }
  }

  static Future<void> _markResult(
    DatabaseExecutor db,
    int id,
    int usedBy,
    String result,
    int now,
  ) async {
    await db.update(
      DbTables.overrideTokens,
      {'used_at_ms': now, 'used_by_user_id': usedBy, 'result': result},
      where: 'id = ?',
      whereArgs: [id],
    );
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

  static Future<Map<String, dynamic>> _postJson({
    required String baseUrl,
    required String path,
    String? apiKey,
    required Map<String, dynamic> payload,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);
    final headers = <String, String>{};
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      headers['x-override-key'] = apiKey.trim();
    }

    final response = await api.postJson(
      path,
      headers: headers,
      body: payload,
      timeout: defaultRemoteTimeout,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<AuthorizationResult> _verifyRemoteToken({
    required String baseUrl,
    String? apiKey,
    required String token,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int usedByUserId,
    required String terminalId,
  }) async {
    try {
      await _postJson(
        baseUrl: baseUrl,
        path: '/api/override/verify',
        apiKey: apiKey,
        payload: {
          'companyId': companyId,
          'token': token,
          'actionCode': actionCode,
          'resourceType': resourceType,
          'resourceId': resourceId,
          'usedById': usedByUserId,
          'terminalId': terminalId,
        },
      );
      return AuthorizationResult(
        success: true,
        message: 'Autorizacion aprobada',
        method: OverrideMethod.remote,
      );
    } catch (_) {
      return AuthorizationResult(
        success: false,
        message: 'Token remoto invalido',
        method: OverrideMethod.remote,
      );
    }
  }

  static Future<void> _storeRemoteApproval({
    required DatabaseExecutor db,
    required String token,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int usedByUserId,
    required String terminalId,
    int? requestId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tokenHash = _hashToken(token);

    await db.insert(DbTables.overrideTokens, {
      'company_id': companyId,
      'action_code': actionCode,
      'resource_type': resourceType,
      'resource_id': resourceId,
      'token_hash': tokenHash,
      'payload_signature': null,
      'method': _methodToString(OverrideMethod.remote),
      'nonce': _randomToken(8),
      'requested_by_user_id': usedByUserId,
      'approved_by_user_id': null,
      'terminal_id': terminalId,
      'expires_at_ms': now + defaultTtl.inMilliseconds,
      'used_at_ms': now,
      'used_by_user_id': usedByUserId,
      'result': 'approved',
      'meta': requestId != null ? jsonEncode({'request_id': requestId}) : null,
      'created_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (requestId != null) {
      await db.update(
        DbTables.overrideRequests,
        {'status': 'approved', 'resolved_at_ms': now},
        where: 'id = ?',
        whereArgs: [requestId],
      );
    }

    await _logAudit(
      db: db,
      companyId: companyId,
      actionCode: actionCode,
      resourceType: resourceType,
      resourceId: resourceId,
      requestedBy: usedByUserId,
      approvedBy: null,
      method: OverrideMethod.remote,
      result: 'approved',
      terminalId: terminalId,
      meta: requestId != null ? {'request_id': requestId} : null,
    );
  }
}
