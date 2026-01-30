import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../features/settings/data/business_settings_repository.dart';
import '../db/app_db.dart';
import '../db/tables.dart';

class RemoteHttpException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;

  RemoteHttpException(this.statusCode, this.message, {this.errorCode});

  @override
  String toString() => message;
}

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

  // Throttle para evitar spam de sync en cada autorización.
  static int? _lastUsersSyncAtMs;

  static Future<Map<String, String>> _loadCompanyCloudHints() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      final hints = <String, String>{};
      final cloudId = settings.cloudCompanyId?.trim();
      final rnc = settings.rnc?.trim();
      if (cloudId != null && cloudId.isNotEmpty)
        hints['companyCloudId'] = cloudId;
      if (rnc != null && rnc.isNotEmpty) hints['companyRnc'] = rnc;
      return hints;
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<Set<String>> _getUserTableColumns(DatabaseExecutor db) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info(${DbTables.users})');
      return rows
          .map((r) => r['name'])
          .whereType<String>()
          .map((s) => s.toLowerCase())
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<Map<String, String>> _loadLocalUserIdentity({
    required DatabaseExecutor db,
    required int userId,
  }) async {
    final cols = await _getUserTableColumns(db);
    final select = <String>['username'];
    if (cols.contains('email')) select.add('email');

    final rows = await db.query(
      DbTables.users,
      columns: select,
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return <String, String>{};

    final row = rows.first;
    final username = (row['username']?.toString() ?? '').trim();
    final email = (row['email']?.toString() ?? '').trim().toLowerCase();

    final result = <String, String>{};
    if (username.isNotEmpty) result['userUsername'] = username;
    if (email.isNotEmpty) result['userEmail'] = email;
    return result;
  }

  static Future<void> _syncUsersToCloudIfNeeded({
    required int companyId,
    required String baseUrl,
    String? apiKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastUsersSyncAtMs;
    if (last != null &&
        now - last < const Duration(minutes: 5).inMilliseconds) {
      return;
    }
    _lastUsersSyncAtMs = now;

    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return;
      if (baseUrl.trim().isEmpty) return;

      final db = await AppDb.database;
      final cols = await _getUserTableColumns(db);

      final whereParts = <String>['company_id = ?'];
      final whereArgs = <Object?>[companyId];
      if (cols.contains('deleted_at_ms'))
        whereParts.add('deleted_at_ms IS NULL');
      if (cols.contains('is_active')) whereParts.add('is_active = 1');

      final select = <String>['username', 'role'];
      if (cols.contains('email')) select.add('email');
      // Variantes comunes de nombre.
      if (cols.contains('display_name')) select.add('display_name');
      if (!cols.contains('display_name') && cols.contains('name'))
        select.add('name');

      final rows = await db.query(
        DbTables.users,
        columns: select,
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
      );

      final users = <Map<String, dynamic>>[];
      for (final r in rows) {
        final username = (r['username']?.toString() ?? '').trim();
        if (username.isEmpty) continue;

        final role = (r['role']?.toString() ?? 'cashier').trim();
        final email = (r['email']?.toString() ?? '').trim();
        final displayName =
            (r['display_name']?.toString() ?? r['name']?.toString() ?? '')
                .trim();

        users.add({
          'username': username,
          if (email.isNotEmpty) 'email': email,
          if (displayName.isNotEmpty) 'displayName': displayName,
          if (role.isNotEmpty) 'role': role,
          'isActive': true,
        });
      }

      if (users.isEmpty) return;

      await _postJson(
        baseUrl: baseUrl,
        path: '/api/auth/sync-users',
        apiKey: apiKey ?? settings.cloudApiKey,
        payload: {
          'companyRnc': settings.rnc,
          'companyCloudId': settings.cloudCompanyId,
          'companyName': settings.businessName,
          'users': users,
        },
      );
    } catch (_) {
      // Best-effort: no bloquear flujo principal.
    }
  }

  static String normalizeOverrideToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return '';
    // Permitir pegar tokens con espacios/guiones y ser tolerantes a minÃºsculas.
    return trimmed.replaceAll(RegExp(r'[\s\-]+'), '').toUpperCase();
  }

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
    final normalizedToken = normalizeOverrideToken(token);
    final tokenHash = _hashToken(normalizedToken);
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
      token: normalizedToken,
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
      token: normalizedToken,
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
    await _syncUsersToCloudIfNeeded(
      companyId: companyId,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );

    final db = await AppDb.database;
    final identity = await _loadLocalUserIdentity(
      db: db,
      userId: requestedByUserId,
    );

    final hints = await _loadCompanyCloudHints();
    final payload = {
      'companyId': companyId,
      ...hints,
      'actionCode': actionCode,
      'resourceType': resourceType,
      'resourceId': resourceId,
      ...identity,
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

  static Future<AuthorizationResult> consumeApprovedRemoteOverrideRequest({
    required String baseUrl,
    String? apiKey,
    required int requestId,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int usedByUserId,
    required String terminalId,
    Map<String, dynamic>? meta,
  }) async {
    try {
      await _syncUsersToCloudIfNeeded(
        companyId: companyId,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );

      final db = await AppDb.database;
      final identity = await _loadLocalUserIdentity(
        db: db,
        userId: usedByUserId,
      );
      final hints = await _loadCompanyCloudHints();

      await _postJson(
        baseUrl: baseUrl,
        path: '/api/override/request/consume',
        apiKey: apiKey,
        payload: {
          'requestId': requestId,
          'companyId': companyId,
          ...hints,
          'actionCode': actionCode,
          'resourceType': resourceType,
          'resourceId': resourceId,
          'usedById': usedByUserId,
          ...identity,
          'terminalId': terminalId,
          if (meta != null) 'meta': meta,
        },
      );

      await _storeRemoteApprovalConsumed(
        db: db,
        actionCode: actionCode,
        resourceType: resourceType,
        resourceId: resourceId,
        companyId: companyId,
        usedByUserId: usedByUserId,
        terminalId: terminalId,
        requestId: requestId,
      );

      return AuthorizationResult(
        success: true,
        message: 'Autorización aprobada',
        method: OverrideMethod.remote,
      );
    } catch (e) {
      if (e is RemoteHttpException) {
        // 409 = aún pendiente (esperable en polling)
        if (e.statusCode == 409) {
          return AuthorizationResult(
            success: false,
            message: e.message,
            method: OverrideMethod.remote,
          );
        }
      }

      String msg = 'No se pudo completar la autorización remota';
      final raw = e.toString();
      if (raw.isNotEmpty) msg = raw.replaceFirst('Exception: ', '').trim();
      return AuthorizationResult(
        success: false,
        message: msg,
        method: OverrideMethod.remote,
      );
    }
  }

  static String _hashToken(String token) {
    final normalized = normalizeOverrideToken(token);
    final bytes = utf8.encode(normalized);
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
    var normalizedBaseUrl = baseUrl.trim();
    if (!normalizedBaseUrl.startsWith('http://') &&
        !normalizedBaseUrl.startsWith('https://')) {
      normalizedBaseUrl = 'https://$normalizedBaseUrl';
    }

    final base = Uri.parse(normalizedBaseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final extraPath = path.startsWith('/') ? path : '/$path';
    // Importante: conservar cualquier prefijo de path del endpoint.
    // Ej: https://host/prefix + /api/override/verify => https://host/prefix/api/override/verify
    final uri = base.replace(path: '$basePath$extraPath');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      headers['x-override-key'] = apiKey.trim();
    }

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(payload))
        .timeout(defaultRemoteTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      String? errorCode;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          if (decoded['message'] != null) {
            message = decoded['message']?.toString();
          }
          if (decoded['errorCode'] != null) {
            errorCode = decoded['errorCode']?.toString();
          }
        }
      } catch (_) {
        // Ignore parse errors; fallback to status code.
      }

      throw RemoteHttpException(
        response.statusCode,
        message?.trim().isNotEmpty == true
            ? message!.trim()
            : 'HTTP ${response.statusCode}',
        errorCode: errorCode,
      );
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
      await _syncUsersToCloudIfNeeded(
        companyId: companyId,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );

      final db = await AppDb.database;
      final identity = await _loadLocalUserIdentity(
        db: db,
        userId: usedByUserId,
      );

      final hints = await _loadCompanyCloudHints();
      await _postJson(
        baseUrl: baseUrl,
        path: '/api/override/verify',
        apiKey: apiKey,
        payload: {
          'companyId': companyId,
          ...hints,
          'token': token,
          'actionCode': actionCode,
          'resourceType': resourceType,
          'resourceId': resourceId,
          ...identity,
          'terminalId': terminalId,
        },
      );
      return AuthorizationResult(
        success: true,
        message: 'Autorizacion aprobada',
        method: OverrideMethod.remote,
      );
    } catch (e) {
      String msg = 'Token remoto invalido';
      final raw = e.toString();
      if (raw.isNotEmpty) {
        // Normalizar "Exception: ..." para UI.
        msg = raw.replaceFirst('Exception: ', '').trim();
      }
      return AuthorizationResult(
        success: false,
        message: msg,
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

  static Future<void> _storeRemoteApprovalConsumed({
    required DatabaseExecutor db,
    required String actionCode,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int usedByUserId,
    required String terminalId,
    required int requestId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      DbTables.overrideRequests,
      {'status': 'consumed', 'resolved_at_ms': now},
      where: 'id = ?',
      whereArgs: [requestId],
    );

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
      meta: {'request_id': requestId, 'mode': 'direct'},
    );
  }
}
