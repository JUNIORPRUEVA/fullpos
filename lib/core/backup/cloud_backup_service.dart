import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/settings/data/business_settings_repository.dart';
import '../config/backend_config.dart';
import '../logging/app_logger.dart';

class CloudBackupUploadResult {
  CloudBackupUploadResult({
    required this.ok,
    this.cloudBackupId,
    this.message,
  });

  final bool ok;
  final String? cloudBackupId;
  final String? message;
}

class CloudBackupEntry {
  CloudBackupEntry({
    required this.id,
    required this.createdAtIso,
    required this.sizeBytes,
    required this.checksumSha256,
    required this.dbVersion,
    required this.appVersion,
    required this.status,
  });

  final String id;
  final String createdAtIso;
  final int sizeBytes;
  final String checksumSha256;
  final int dbVersion;
  final String appVersion;
  final String status;

  factory CloudBackupEntry.fromJson(Map<String, dynamic> json) {
    return CloudBackupEntry(
      id: json['id'] as String,
      createdAtIso: json['created_at'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int? ?? 0,
      checksumSha256: json['sha256'] as String? ?? '',
      dbVersion: json['db_version'] as int? ?? 0,
      appVersion: json['app_version'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'UNKNOWN',
    );
  }
}

class CloudBackupService {
  CloudBackupService._();

  static final CloudBackupService instance = CloudBackupService._();

  Future<CloudBackupUploadResult> uploadBackup({
    required String filePath,
    required int sizeBytes,
    required String checksumSha256,
    required int dbVersion,
    required String appVersion,
    required String deviceId,
    required int userId,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final baseUrl =
        (settings.cloudEndpoint?.trim().isNotEmpty ?? false)
            ? settings.cloudEndpoint!.trim()
            : backendBaseUrl;
    final cloudKey = settings.cloudApiKey?.trim();
    final companyCloudId = settings.cloudCompanyId?.trim();
    final rnc = settings.rnc?.trim();

    if (cloudKey == null || cloudKey.isEmpty) {
      return CloudBackupUploadResult(
        ok: false,
        message: 'API key requerida',
      );
    }

    final uri = Uri.parse(baseUrl).replace(path: '/api/backups/create');
    final request = http.MultipartRequest('POST', uri);
    request.headers['x-cloud-key'] = cloudKey;
    request.fields['deviceId'] = deviceId;
    request.fields['dbVersion'] = dbVersion.toString();
    request.fields['appVersion'] = appVersion;
    request.fields['checksumSha256'] = checksumSha256;
    request.fields['sizeBytes'] = sizeBytes.toString();
    request.fields['userId'] = userId.toString();
    if (companyCloudId != null && companyCloudId.isNotEmpty) {
      request.fields['companyCloudId'] = companyCloudId;
    }
    if (rnc != null && rnc.isNotEmpty) {
      request.fields['companyRnc'] = rnc;
    }

    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    try {
      final response = await request.send();
      final payload = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CloudBackupUploadResult(
          ok: false,
          message: payload.isNotEmpty ? payload : 'Error subiendo backup',
        );
      }
      final jsonBody = jsonDecode(payload) as Map<String, dynamic>;
      return CloudBackupUploadResult(
        ok: jsonBody['ok'] == true,
        cloudBackupId: jsonBody['cloud_backup_id'] as String?,
        message: jsonBody['message'] as String?,
      );
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud backup upload error: $e',
        module: 'backup_cloud',
      );
      return CloudBackupUploadResult(
        ok: false,
        message: 'Error de red subiendo backup',
      );
    }
  }

  Future<List<CloudBackupEntry>> listBackups() async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final baseUrl =
        (settings.cloudEndpoint?.trim().isNotEmpty ?? false)
            ? settings.cloudEndpoint!.trim()
            : backendBaseUrl;
    final cloudKey = settings.cloudApiKey?.trim();
    final companyCloudId = settings.cloudCompanyId?.trim();
    final rnc = settings.rnc?.trim();

    if (cloudKey == null || cloudKey.isEmpty) return [];
    final uri = Uri.parse(baseUrl).replace(
      path: '/api/backups/list',
      queryParameters: {
        if (companyCloudId != null && companyCloudId.isNotEmpty)
          'companyCloudId': companyCloudId,
        if (rnc != null && rnc.isNotEmpty) 'companyRnc': rnc,
      },
    );
    try {
      final response = await http.get(
        uri,
        headers: {'x-cloud-key': cloudKey},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return [];
      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(CloudBackupEntry.fromJson)
          .toList();
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud list backups error: $e',
        module: 'backup_cloud',
      );
      return [];
    }
  }

  Future<File?> downloadBackup({
    required String cloudBackupId,
    required Directory outDir,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final baseUrl =
        (settings.cloudEndpoint?.trim().isNotEmpty ?? false)
            ? settings.cloudEndpoint!.trim()
            : backendBaseUrl;
    final cloudKey = settings.cloudApiKey?.trim();

    if (cloudKey == null || cloudKey.isEmpty) return null;
    final uri = Uri.parse(baseUrl)
        .replace(path: '/api/backups/download/$cloudBackupId');
    try {
      final response = await http.get(
        uri,
        headers: {'x-cloud-key': cloudKey},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final file = File('${outDir.path}/cloud_backup_$cloudBackupId.zip');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud download error: $e',
        module: 'backup_cloud',
      );
      return null;
    }
  }

  Future<bool> validateBackup({
    required String cloudBackupId,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final baseUrl =
        (settings.cloudEndpoint?.trim().isNotEmpty ?? false)
            ? settings.cloudEndpoint!.trim()
            : backendBaseUrl;
    final cloudKey = settings.cloudApiKey?.trim();

    if (cloudKey == null || cloudKey.isEmpty) return false;
    final uri = Uri.parse(baseUrl).replace(path: '/api/backups/restore/validate');
    try {
      final response = await http
          .post(
            uri,
            headers: {
              'x-cloud-key': cloudKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'cloudBackupId': cloudBackupId}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
      return jsonBody['ok'] == true;
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud validate error: $e',
        module: 'backup_cloud',
      );
      return false;
    }
  }

  Future<bool> resetCompany({
    required String phrase,
    required String adminPin,
  }) async {
    return _dangerAction(
      action: 'RESET',
      phrase: phrase,
      adminPin: adminPin,
    );
  }

  Future<bool> deleteCompany({
    required String phrase,
    required String adminPin,
  }) async {
    return _dangerAction(
      action: 'DELETE',
      phrase: phrase,
      adminPin: adminPin,
    );
  }

  Future<bool> _dangerAction({
    required String action,
    required String phrase,
    required String adminPin,
  }) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final baseUrl =
        (settings.cloudEndpoint?.trim().isNotEmpty ?? false)
            ? settings.cloudEndpoint!.trim()
            : backendBaseUrl;
    final cloudKey = settings.cloudApiKey?.trim();
    final companyCloudId = settings.cloudCompanyId?.trim();
    final rnc = settings.rnc?.trim();

    if (cloudKey == null || cloudKey.isEmpty) return false;
    if ((companyCloudId == null || companyCloudId.isEmpty) &&
        (rnc == null || rnc.isEmpty)) {
      return false;
    }

    final uri = Uri.parse(baseUrl).replace(
      path: '/api/company/actions',
    );
    try {
      final response = await http
          .post(
            uri,
            headers: {
              'x-cloud-key': cloudKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'action': action,
              'phrase': phrase,
              'adminPin': adminPin,
              if (companyCloudId != null && companyCloudId.isNotEmpty)
                'companyCloudId': companyCloudId,
              if (rnc != null && rnc.isNotEmpty) 'companyRnc': rnc,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
      return jsonBody['ok'] == true;
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud danger action error: $e',
        module: 'backup_cloud',
      );
      return false;
    }
  }
}
